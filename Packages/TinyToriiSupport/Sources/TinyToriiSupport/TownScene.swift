import Foundation
import GeometryLite3D
import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh

// Keeps a scene graph in step with a Town. Cells are merged into chunks, so the renderer sees few nodes; a cell whose
// item just changed gets its own node for a moment, to pop in.
@MainActor
public final class TownScene {
    public let sceneGraph: SceneGraph
    public private(set) var town: Town
    public private(set) var time: TimeOfDay
    let device: MTLDevice
    let root: SceneGraph.Node
    private let world: SceneGraph.Node
    private let sun: SceneGraph.Node
    private let fill: SceneGraph.Node
    private let lamps: SceneGraph.Node
    private let highlight: SceneGraph.Node
    private var sea: SceneGraph.Node?
    private let atmosphere: Atmosphere
    private let villagers: Villagers
    private let creatures: Creatures
    private var groundBuilders: [MeshBuilder?] = []
    private var itemBuilders: [MeshBuilder?] = []
    private var shownItems: [Item?] = []
    private var chunkOfCell: [Int] = []
    private var chunkCells: [[Int]] = []
    private var chunkNodes: [SceneGraph.Node?] = []
    private var chunkMeshes: [MeshBuilder.Built?] = []
    private var popNodes: [Int: (node: SceneGraph.Node, built: MeshBuilder.Built)] = [:]
    // The highest point of each cell, for picking.
    private(set) var cellTops: [Float] = []
    private var materials: [Surface: BlinnPhongSceneMaterial] = [:]
    private var albedoTexture: MTLTexture?

    static let chunkSize: Float = 91

    public init(town: Town, time: TimeOfDay = .day, device: MTLDevice? = nil) {
        let device = device ?? MTLCreateSystemDefaultDevice()!
        self.device = device
        self.town = town
        self.time = time
        root = SceneGraph.Node(label: "Root")
        world = SceneGraph.Node(parent: root, label: "Town")
        sun = SceneGraph.Node(parent: root, label: "Sun", content: .light(Light(type: .directional, color: time.sunColor, intensity: time.sunIntensity)))
        fill = SceneGraph.Node(parent: root, label: "Fill", content: .light(Light(type: .directional, color: [0.55, 0.65, 0.9], intensity: 0.3)))
        lamps = SceneGraph.Node(parent: root, label: "Lamps")
        highlight = SceneGraph.Node(parent: root, label: "Highlight")
        atmosphere = Atmosphere(parent: root)
        villagers = Villagers(parent: root)
        creatures = Creatures(parent: root)
        sceneGraph = SceneGraph(root: root)
        applyTime()
        reset()
    }

    // Sizes everything for the town's grid and builds it all.
    private func reset() {
        world.removeAllChildren()
        popNodes.removeAll()
        let count = town.grid.cells.count
        groundBuilders = Array(repeating: nil, count: count)
        itemBuilders = Array(repeating: nil, count: count)
        shownItems = Array(repeating: nil, count: count)
        cellTops = Array(repeating: 0, count: count)
        var chunkIndex: [SIMD2<Int32>: Int] = [:]
        chunkCells = []
        chunkOfCell = town.grid.cells.map { cell in
            let key = SIMD2<Int32>(Int32((cell.center.x / Self.chunkSize).rounded(.down)), Int32((cell.center.y / Self.chunkSize).rounded(.down)))
            if let index = chunkIndex[key] {
                return index
            }
            chunkIndex[key] = chunkCells.count
            chunkCells.append([])
            return chunkCells.count - 1
        }
        for (cell, chunk) in chunkOfCell.enumerated() {
            chunkCells[chunk].append(cell)
        }
        chunkNodes = Array(repeating: nil, count: chunkCells.count)
        chunkMeshes = Array(repeating: nil, count: chunkCells.count)
        sea?.removeFromParent()
        buildSea()
        rebuild(Set(0..<count), animated: false)
        villagers.reset(scene: self)
    }

    public var cellCount: Int {
        town.grid.cells.count
    }

    // Moves the villagers; call once a frame.
    public func advance(by deltaTime: Float) {
        villagers.advance(by: min(deltaTime, 0.05), scene: self)
        creatures.advance(by: min(deltaTime, 0.05))
    }

    public func top(of cell: Int) -> Float {
        cellTops[cell]
    }

    // MARK: - Editing

    public func update(_ change: (inout Town) -> Set<Int>) {
        let cells = change(&town)
        rebuild(cells, animated: true)
    }

    public func replace(town newTown: Town) {
        let sameGrid = newTown.gridSeed == town.gridSeed && newTown.cells.count == town.cells.count
        town = newTown
        if sameGrid {
            rebuild(Set(0..<cellCount), animated: false)
            villagers.reset(scene: self)
        } else {
            reset()
        }
    }

    func material(_ surface: Surface) -> BlinnPhongSceneMaterial {
        if let material = materials[surface] {
            return material
        }
        let albedo = albedoTexture ?? PaletteTextures.make(device: device, time: nil)
        albedoTexture = albedo
        let material = PaletteTextures.material(surface: surface, albedo: albedo, glow: PaletteTextures.make(device: device, time: time))
        materials[surface] = material
        return material
    }

    func materials(for built: MeshBuilder.Built) -> [any SceneSprockets.Material] {
        built.surfaces.map { material($0) }
    }

    private func content(for built: MeshBuilder.Built, castsShadow: Bool = true) -> SceneGraph.Node.Content {
        .mesh(built.mesh, materials: materials(for: built), castsShadow: castsShadow, receivesShadow: true)
    }

    func rebuild(_ cells: Set<Int>, animated: Bool) {
        var dirtyChunks = Set<Int>()
        for cell in cells {
            let center = town.grid.cells[cell].center
            let base = town.standingHeight(cell)
            let ground = MeshBuilder()
            GroundMesher.build(ground, town: town, cell: cell)
            groundBuilders[cell] = ground

            let item = town.cells[cell].item
            var itemBuilder: MeshBuilder?
            if let item {
                let builder = MeshBuilder()
                buildItem(builder, item: item, cell: cell, center: center, base: base, local: false)
                itemBuilder = builder
            }
            itemBuilders[cell] = itemBuilder
            cellTops[cell] = max(town.groundHeight(cell), itemBuilder.map(\.maxY) ?? -.infinity)

            let changed = shownItems[cell] != item
            let grew = shownItems[cell]?.kind == item?.kind
            shownItems[cell] = item
            if animated, changed, let item {
                pop(cell: cell, item: item, grew: grew)
            } else if changed, let pop = popNodes.removeValue(forKey: cell) {
                pop.node.removeFromParent()
            }
            dirtyChunks.insert(chunkOfCell[cell])
        }
        for chunk in dirtyChunks {
            rebuildChunk(chunk)
        }
        updateLamps()
        atmosphere.update(town: town, time: time)
        creatures.sync(scene: self)
    }

    private func pop(cell: Int, item: Item, grew: Bool) {
        popNodes.removeValue(forKey: cell)?.node.removeFromParent()
        let center = town.grid.cells[cell].center
        let base = town.standingHeight(cell)
        let builder = MeshBuilder()
        buildItem(builder, item: item, cell: cell, center: center, base: base, local: true)
        guard let built = builder.build(device: device, label: "Pop \(cell)") else {
            return
        }
        let node = SceneGraph.Node(parent: world, label: "Pop \(cell)", content: content(for: built))
        node.trs = Transform3D(translation: center.lifted(base), scale: SIMD3(repeating: grew ? 0.85 : 0.05))
        popNodes[cell] = (node, built)
        node.run(.sequence([.scale(to: [1.06, 1.06, 1.06], duration: grew ? 0.14 : 0.24), .scale(to: [1, 1, 1], duration: 0.08)])) { [weak self, weak node] in
            MainActor.assumeIsolated {
                guard let self, let node, self.popNodes[cell]?.node === node else {
                    return
                }
                self.popNodes.removeValue(forKey: cell)
                node.removeFromParent()
                self.rebuildChunk(self.chunkOfCell[cell])
            }
        }
    }

    private func rebuildChunk(_ chunk: Int) {
        let builder = MeshBuilder()
        for cell in chunkCells[chunk] {
            if let ground = groundBuilders[cell] {
                builder.append(ground)
            }
            if popNodes[cell] == nil, let item = itemBuilders[cell] {
                builder.append(item)
            }
        }
        let built = builder.build(device: device, label: "Chunk \(chunk)")
        chunkMeshes[chunk] = built
        if let built {
            if let node = chunkNodes[chunk] {
                node.content = content(for: built)
            } else {
                chunkNodes[chunk] = SceneGraph.Node(parent: world, label: "Chunk \(chunk)", content: content(for: built))
            }
        } else {
            chunkNodes[chunk]?.removeFromParent()
            chunkNodes[chunk] = nil
        }
    }

    // `local`: relative to the cell center at standing height, for a node that scales around it.
    private func buildItem(_ builder: MeshBuilder, item: Item, cell: Int, center: SIMD2<Float>, base: Float, local: Bool) {
        let origin = simd_float4x4(translation: center.lifted(base))
        if item.kind.isBuilding {
            builder.setTransform(local ? origin.inverse : matrix_identity_float4x4)
            BuildingMesher.build(builder, town: town, cell: cell, item: item)
            return
        }
        let rotation = simd_quatf(angle: -item.rotation, axis: [0, 1, 0])
        builder.setTransform((local ? matrix_identity_float4x4 : origin) * simd_float4x4(rotation))
        switch item.kind.category {
        case .trees:
            TreeMesher.build(builder, item: item)
        default:
            let inverse = rotation.inverse
            let polygon = town.grid.polygon(of: cell).map { inverse.act(($0 - center).lifted(0)).xz }
            let joined = town.grid.cells[cell].neighbors.map { neighbor in
                neighbor.flatMap { town.cells[$0].item?.kind } == item.kind
            }
            PropMesher.build(builder, item: item, polygon: polygon, joined: joined)
        }
    }

    // MARK: - Time of day

    public func setTime(_ newTime: TimeOfDay) {
        guard newTime != time else {
            return
        }
        time = newTime
        materials.removeAll()
        applyTime()
        for (chunk, built) in chunkMeshes.enumerated() {
            if let built, let node = chunkNodes[chunk] {
                node.content = content(for: built)
            }
        }
        for pop in popNodes.values {
            pop.node.content = content(for: pop.built)
        }
        updateLamps()
        atmosphere.update(town: town, time: time)
        villagers.refreshMaterials(scene: self)
        creatures.refreshMaterials(scene: self)
    }

    private func applyTime() {
        sun.content = .light(Light(type: .directional, color: time.sunColor, intensity: time.sunIntensity))
        sun.transform = LookAt(position: time.sunDirection * 140, target: .zero, up: [0, 1, 0]).cameraMatrix
        fill.content = .light(Light(type: .directional, color: time == .night ? [0.2, 0.25, 0.5] : [0.55, 0.65, 0.9], intensity: time == .night ? 0.15 : 0.3, castsShadow: false))
        fill.transform = LookAt(position: [-70, 42, -87.5], target: .zero, up: [0, 1, 0]).cameraMatrix
        // A background gradient, not a sky mesh: shadows fit the scene's bounds, so the scene must stay small.
        sceneGraph.environment.background = .gradient(.init(zenith: time.skyTop, horizon: time.seaDistance, ground: time.seaDistance, exponent: 0.6))
        sceneGraph.fog = SceneGraph.Fog(color: SIMD4(time.seaDistance, 1), startDistance: 157.5, endDistance: 437.5, densityExponent: 1.2)
    }

    // At dusk and night, the lanterns cast real light: a few point lights spread over the town.
    private func updateLamps() {
        lamps.removeAllChildren()
        guard time == .night || time == .dusk else {
            return
        }
        var candidates: [SIMD3<Float>] = []
        for cell in 0..<cellCount {
            guard let item = town.cells[cell].item else {
                continue
            }
            let height: Float? = switch item.kind {
            case .stoneLantern: 2.45
            case .paperLantern: 3.5
            case .ryokan, .machiya: 1.75
            case .shrine, .temple: 2.8
            default: nil
            }
            if let height {
                candidates.append(town.grid.cells[cell].center.lifted(town.standingHeight(cell) + height))
            }
        }
        // Farthest-point sampling keeps them spread out.
        var chosen: [SIMD3<Float>] = []
        let limit = 10
        while chosen.count < limit, !candidates.isEmpty {
            let index = candidates.indices.max { a, b in
                let da = chosen.map { simd_distance($0, candidates[a]) }.min() ?? .infinity
                let db = chosen.map { simd_distance($0, candidates[b]) }.min() ?? .infinity
                return da < db
            }!
            chosen.append(candidates.remove(at: index))
        }
        for position in chosen {
            let node = SceneGraph.Node(parent: lamps, label: "Lamp", content: .light(Light(type: .point, color: [1, 0.62, 0.3], intensity: time == .night ? 30 : 15, range: 21, castsShadow: false)))
            node.trs = Transform3D(translation: position)
        }
    }

    // MARK: - Sea

    private func buildSea() {
        let builder = MeshBuilder()
        let sides = 64
        let points = (0..<sides).map { index -> SIMD3<Float> in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return [cos(angle) * town.grid.radius * 2.6, GroundMesher.seaLevel, sin(angle) * town.grid.radius * 2.6]
        }
        builder.cap(.sea, points)
        // Little whitecaps around the coast.
        var random = SeededRandom(seed: town.gridSeed &+ 5)
        for _ in 0..<70 {
            let angle = random.range(0, 2 * .pi)
            let distance = town.grid.radius * random.range(1.15, 1.45)
            builder.blob(.foxWhite, center: [cos(angle) * distance, GroundMesher.seaLevel, sin(angle) * distance], scale: [random.range(1.05, 2.8), 0.07, 0.21], rotation: simd_quatf(angle: -angle + .pi / 2, axis: [0, 1, 0]))
        }
        if let built = builder.build(device: device, label: "Sea") {
            sea = SceneGraph.Node(parent: root, label: "Sea", content: content(for: built, castsShadow: false))
        }
    }

    // MARK: - Picking and highlight

    public func pick(ray: Ray3D) -> Int? {
        let grid = town.grid
        var best: (cell: Int, distance: Float)?
        for cell in 0..<cellCount {
            let top = cellTops[cell]
            let points = grid.polygon(of: cell)
            // Top face.
            if abs(ray.direction.y) > 1e-5 {
                let t = (top - ray.origin.y) / ray.direction.y
                if t > 0, t < best?.distance ?? .infinity {
                    let hit = ray.origin + ray.direction * t
                    if GroundMesher.insidePolygon(hit.xz, points) {
                        best = (cell, t)
                    }
                }
            }
            // Side faces.
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                let edge = b - a
                let normal = SIMD2<Float>(-edge.y, edge.x)
                let denominator = simd_dot(normal, ray.direction.xz)
                guard abs(denominator) > 1e-6 else {
                    continue
                }
                let t = simd_dot(normal, a - ray.origin.xz) / denominator
                guard t > 0, t < best?.distance ?? .infinity else {
                    continue
                }
                let hit = ray.origin + ray.direction * t
                let along = simd_dot(hit.xz - a, edge) / simd_length_squared(edge)
                if along >= 0, along <= 1, hit.y <= top, hit.y >= GroundMesher.seaFloor {
                    best = (cell, t)
                }
            }
        }
        return best?.cell
    }

    public func setHighlight(_ cells: [Int], stretching: Bool = false) {
        highlight.removeAllChildren()
        guard !cells.isEmpty else {
            return
        }
        let builder = MeshBuilder()
        for cell in cells {
            let points = town.grid.polygon(of: cell)
            let center = town.grid.cells[cell].center
            let y = town.groundHeight(cell) + 0.14
            for index in points.indices {
                let a = center + (points[index] - center) * 0.9
                let b = center + (points[(index + 1) % points.count] - center) * 0.9
                builder.beam(stretching ? .highlightStretch : .highlight, from: a.lifted(y), to: b.lifted(y), width: 0.245, height: 0.105)
            }
        }
        if let built = builder.build(device: device, label: "Highlight") {
            _ = SceneGraph.Node(parent: highlight, label: "Outline", content: .mesh(built.mesh, materials: materials(for: built), castsShadow: false, receivesShadow: false))
        }
    }

    // MARK: - Walking

    public func walkHeight(at point: SIMD2<Float>) -> Float? {
        guard let cell = town.grid.cell(at: point) else {
            return nil
        }
        return town.standingHeight(cell)
    }

    public func isWalkable(_ point: SIMD2<Float>, from current: Float) -> Bool {
        guard let cell = town.grid.cell(at: point) else {
            return false
        }
        let state = town.cells[cell]
        if let item = state.item, item.kind.blocksWalking {
            return false
        }
        if state.ground == .water && state.item?.kind != .bridge {
            return false
        }
        // Trunks, lanterns and statues stand at the cell center.
        if let item = state.item {
            let radius: Float = switch item.kind {
            case .bamboo: 2.625
            case .zenGarden, .stones, .azalea: 1.925
            case .sakura, .ume, .momiji, .pine, .sugi, .ginkgo, .willow, .stoneLantern, .foxStatue: 1.05
            default: 0
            }
            if radius > 0, simd_distance(point, town.grid.cells[cell].center) < radius {
                return false
            }
        }
        return town.standingHeight(cell) - current < Town.elevationStep * 1.1
    }
}

extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
