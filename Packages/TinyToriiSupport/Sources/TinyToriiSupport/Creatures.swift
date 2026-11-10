import GeometryLite3D
import Metal
import SceneSprockets
import simd

// Animals that live on a cell and potter about it: cranes wade, frogs hop, foxes trot, cats nap, koi circle and
// tanuki snuffle. A cell's level is how many there are. Forward is +z.
@MainActor
final class Creatures {
    private struct Creature {
        var node: SceneGraph.Node
        var kind: Kind
        var look: Int
        var home: SIMD2<Float>
        var radius: Float
        var position: SIMD2<Float>
        var target: SIMD2<Float>
        var heading: Float
        var speed: Float
        var pause: Float
        var phase: Float
        var hop: Float = 0
        var base: Float
    }

    private let parent: SceneGraph.Node
    private var creatures: [Creature] = []
    private var signature: [Int: CellState] = [:]
    private var random = SeededRandom(seed: 808)
    private var looks: [String: MeshBuilder.Built] = [:]

    init(parent: SceneGraph.Node) {
        self.parent = SceneGraph.Node(parent: parent, label: "Creatures")
    }

    static func isCreature(_ item: Item) -> Bool {
        item.kind.category == .animals && !(item.kind == .tanuki && item.style == 1)
    }

    // Rebuilds the animals when the animal cells changed.
    func sync(scene: TownScene) {
        let town = scene.town
        var current: [Int: CellState] = [:]
        for (cell, state) in town.cells.enumerated() {
            if let item = state.item, Self.isCreature(item) {
                current[cell] = state
            }
        }
        // Keep the ones whose cell did not change, so they don't jump.
        let unchanged = Set(current.keys.filter { signature[$0] == current[$0] })
        creatures.removeAll { creature in
            let cell = town.grid.cell(at: creature.home)
            if let cell, unchanged.contains(cell) {
                return false
            }
            creature.node.removeFromParent()
            return true
        }
        for (cell, state) in current where !unchanged.contains(cell) {
            guard let item = state.item else {
                continue
            }
            var random = SeededRandom(seed: item.seed)
            let home = town.grid.cells[cell].center
            let base = town.groundHeight(cell)
            for index in 0..<item.level {
                let angle = Float(index) / Float(item.level) * 2 * .pi + random.range(0, 1)
                let start = home + SIMD2(cos(angle), sin(angle)) * random.range(0.1, 0.45)
                let built = look(kind: item.kind, style: item.style, device: scene.device)
                let node = SceneGraph.Node(parent: parent, label: item.kind.rawValue, content: .mesh(built.mesh, materials: scene.materials(for: built), castsShadow: item.kind != .koi, receivesShadow: true))
                var creature = Creature(node: node, kind: item.kind, look: item.style, home: home, radius: item.kind == .koi ? 0.55 : 0.7, position: start, target: start, heading: random.range(0, 2 * .pi), speed: speed(of: item.kind), pause: random.range(0, 2), phase: random.range(0, 6), base: base)
                place(&creature)
                creatures.append(creature)
            }
        }
        signature = current
    }

    func refreshMaterials(scene: TownScene) {
        for creature in creatures {
            let built = look(kind: creature.kind, style: creature.look, device: scene.device)
            creature.node.content = .mesh(built.mesh, materials: scene.materials(for: built), castsShadow: creature.kind != .koi, receivesShadow: true)
        }
    }

    private func speed(of kind: Kind) -> Float {
        switch kind {
        case .crane: 0.12
        case .frog: 0.5
        case .fox: 0.45
        case .cat: 0.2
        case .koi: 0.18
        default: 0.22
        }
    }

    func advance(by deltaTime: Float) {
        for index in creatures.indices {
            var creature = creatures[index]
            defer { creatures[index] = creature }
            creature.phase += deltaTime
            if creature.pause > 0 {
                creature.pause -= deltaTime
                place(&creature)
                continue
            }
            let delta = creature.target - creature.position
            if simd_length(delta) < 0.04 {
                let angle = random.range(0, 2 * .pi)
                creature.target = creature.home + SIMD2(cos(angle), sin(angle)) * random.range(0.05, creature.radius)
                // Koi keep swimming; the others stop to look about.
                creature.pause = switch creature.kind {
                case .koi: 0
                case .cat: random.chance(0.4) ? random.range(3, 8) : random.range(0.5, 2)
                case .frog: random.range(0.6, 2.5)
                case .crane: random.range(1.5, 4)
                default: random.range(0.5, 2.5)
                }
                continue
            }
            let step = simd_normalize(delta) * min(simd_length(delta), creature.speed * deltaTime)
            creature.position += step
            var turn = atan2(step.x, step.y) - creature.heading
            while turn > .pi { turn -= 2 * .pi }
            while turn < -.pi { turn += 2 * .pi }
            creature.heading += turn * min(1, deltaTime * 5)
            if creature.kind == .frog {
                creature.hop += deltaTime * 4
            }
            place(&creature)
        }
    }

    private func place(_ creature: inout Creature) {
        var y = creature.base
        var tilt = simd_quatf(angle: 0, axis: [1, 0, 0])
        switch creature.kind {
        case .frog:
            y += creature.pause > 0 ? 0 : abs(sin(creature.hop * .pi)) * 0.12
        case .koi:
            y = creature.base + 0.006
            tilt = simd_quatf(angle: sin(creature.phase * 6) * 0.25, axis: [0, 1, 0])
        case .crane:
            if creature.pause > 0 {
                // Dips its head now and then.
                tilt = simd_quatf(angle: max(0, sin(creature.phase * 0.8)) * 0.35, axis: [1, 0, 0])
            }
        default:
            y += creature.pause > 0 ? 0 : abs(sin(creature.phase * 12)) * 0.008
        }
        creature.node.trs = Transform3D(translation: creature.position.lifted(y), rotation: simd_quatf(angle: creature.heading, axis: [0, 1, 0]) * tilt)
    }

    // MARK: - Meshes

    private func look(kind: Kind, style: Int, device: MTLDevice) -> MeshBuilder.Built {
        let key = "\(kind.rawValue)-\(style)"
        if let built = looks[key] {
            return built
        }
        let builder = MeshBuilder()
        Self.mesh(builder, kind: kind, style: style)
        let built = builder.build(device: device, label: key)!
        looks[key] = built
        return built
    }

    nonisolated static func mesh(_ b: MeshBuilder, kind: Kind, style: Int) {
        switch kind {
        case .crane:
            let body: Paint = style == 0 ? .foxWhite : .stoneLight
            b.blob(body, center: [0, 0.32, 0], scale: [0.07, 0.07, 0.13])
            b.blob(.blackWood, center: [0, 0.32, -0.12], scale: [0.06, 0.05, 0.07])
            b.frustum(style == 0 ? .blackWood : .stoneLight, from: [0, 0.36, 0.08], to: [0, 0.55, 0.13], radiusA: 0.02, radiusB: 0.013, sides: 5)
            b.blob(body, center: [0, 0.56, 0.14], scale: SIMD3(repeating: 0.025))
            if style == 0 {
                b.blob(.bib, center: [0, 0.58, 0.14], scale: SIMD3(repeating: 0.013))
            }
            b.cone(.bamboo, base: [0, 0.56, 0.155], tip: [0, 0.55, 0.23], radius: 0.008, sides: 4)
            for side: Float in [-1, 1] {
                b.cylinder(.blackWood, from: [side * 0.025, 0, 0], to: [side * 0.025, 0.28, 0], radius: 0.006, sides: 4)
            }
        case .frog:
            let skin: Paint = style == 0 ? .momijiGreen : .cedar
            b.blob(skin, center: [0, 0.035, 0], scale: [0.045, 0.03, 0.05])
            for side: Float in [-1, 1] {
                b.blob(.foxWhite, center: [side * 0.022, 0.065, 0.03], scale: SIMD3(repeating: 0.014))
                b.blob(.blackWood, center: [side * 0.024, 0.068, 0.04], scale: SIMD3(repeating: 0.007))
                b.blob(skin, center: [side * 0.045, 0.015, -0.025], scale: [0.02, 0.015, 0.035])
            }
        case .fox:
            let fur: Paint = style == 0 ? .momijiOrange : .stoneLight
            do {
                b.append(try ModelLibrary.compile("fox", parameters: ["FUR": ModelLibrary.hex(fur)]))
            } catch {
                assertionFailure("fox.json: \(error)")
            }
        case .cat:
            let fur: Paint = [.foxWhite, .blackWood, .plaster][style]
            quadruped(b, fur: fur, belly: fur, height: 0.08, length: 0.1)
            if style == 0 {
                b.blob(.momijiOrange, center: [0.02, 0.12, -0.03], scale: [0.035, 0.025, 0.05])
                b.blob(.blackWood, center: [-0.025, 0.12, 0.04], scale: [0.03, 0.022, 0.03])
            }
            b.blob(fur, center: [0, 0.15, 0.1], scale: SIMD3(repeating: 0.04))
            for side: Float in [-1, 1] {
                b.cone(style == 0 ? .momijiOrange : fur, base: [side * 0.022, 0.175, 0.1], tip: [side * 0.028, 0.215, 0.1], radius: 0.014, sides: 3)
                b.blob(style == 1 ? .ginkgoYellow : .bamboo, center: [side * 0.016, 0.155, 0.135], scale: SIMD3(repeating: 0.007))
            }
            b.beam(fur, from: [0, 0.1, -0.1], to: [0, 0.22, -0.15], width: 0.016, height: 0.016)
        case .koi:
            let colors: (Paint, Paint) = [(.koiWhite, .koiOrange), (.gold, .gold), (.blackWood, .koiOrange)][style]
            b.blob(colors.0, center: .zero, scale: [0.035, 0.018, 0.09])
            b.blob(colors.1, center: [0, 0.008, 0.03], scale: [0.025, 0.013, 0.04])
            b.blob(colors.1, center: [0, 0.008, -0.04], scale: [0.022, 0.012, 0.03])
            b.cone(colors.0, base: [0, 0, -0.08], tip: [0, 0, -0.14], radius: 0.03, sides: 4)
        case .tanuki:
            quadruped(b, fur: .bark, belly: .cedar, height: 0.09, length: 0.12)
            b.blob(.bark, center: [0, 0.15, 0.12], scale: [0.045, 0.04, 0.045])
            b.blob(.blackWood, center: [0, 0.15, 0.15], scale: [0.042, 0.018, 0.02])
            b.cone(.lightWood, base: [0, 0.145, 0.15], tip: [0, 0.14, 0.2], radius: 0.018, sides: 5)
            b.blob(.blackWood, center: [0, 0.14, 0.2], scale: SIMD3(repeating: 0.008))
            for side: Float in [-1, 1] {
                b.blob(.blackWood, center: [side * 0.03, 0.185, 0.11], scale: SIMD3(repeating: 0.013))
            }
            b.blob(.bark, center: [0, 0.11, -0.13], scale: [0.04, 0.04, 0.07])
            b.blob(.blackWood, center: [0, 0.1, -0.18], scale: SIMD3(repeating: 0.025))
        default:
            break
        }
    }

    nonisolated private static func quadruped(_ b: MeshBuilder, fur: Paint, belly: Paint, height: Float, length: Float) {
        b.blob(fur, center: [0, height + 0.03, 0], scale: [0.05, 0.05, length])
        b.blob(belly, center: [0, height + 0.01, 0.02], scale: [0.035, 0.035, length * 0.7])
        for x: Float in [-0.028, 0.028] {
            for z in [-length * 0.6, length * 0.6] {
                b.cylinder(fur, from: [x, 0, z], to: [x, height + 0.02, z], radius: 0.012, sides: 4)
                b.blob(.blackWood, center: [x, 0.006, z + 0.004], scale: [0.013, 0.008, 0.015])
            }
        }
    }

    // The shigaraki tanuki statue: big belly, straw hat and sake flask.
    nonisolated static func tanukiStatue(_ b: MeshBuilder) {
        b.box(.stone, center: [0, 0.05, 0], size: [0.32, 0.1, 0.32])
        b.blob(.shingle, center: [0, 0.27, 0], scale: [0.14, 0.17, 0.13])
        b.blob(.plasterCream, center: [0, 0.24, 0.07], scale: [0.11, 0.12, 0.08])
        b.blob(.shingle, center: [0, 0.47, 0.01], scale: SIMD3(repeating: 0.08))
        b.blob(.plasterCream, center: [0, 0.45, 0.07], scale: [0.05, 0.035, 0.03])
        for side: Float in [-1, 1] {
            b.blob(.blackWood, center: [side * 0.03, 0.48, 0.075], scale: SIMD3(repeating: 0.012))
            b.blob(.shingle, center: [side * 0.13, 0.28, 0.04], scale: [0.04, 0.09, 0.04])
        }
        b.cone(.thatch, base: [0, 0.53, 0], tip: [0, 0.62, 0], radius: 0.13, sides: 10, capped: true)
        b.blob(.plaster, center: [0.15, 0.2, 0.06], scale: [0.045, 0.06, 0.045])
        b.cylinder(.plaster, from: [0.15, 0.25, 0.06], to: [0.15, 0.29, 0.06], radius: 0.015)
        b.box(.lattice, center: [0.15, 0.2, 0.105], size: [0.04, 0.05, 0.005])
    }
}
