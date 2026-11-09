import GeometryLite3D
import Metal
import SceneSprockets
import simd

// Little people who wander the paths, so the town feels lived in.
@MainActor
final class Villagers {
    private struct Walker {
        var node: SceneGraph.Node
        var position: SIMD2<Float>
        var target: SIMD2<Float>
        var heading: Float
        var speed: Float
        var pause: Float
        var phase: Float
        var recent: [Int]
    }

    private let parent: SceneGraph.Node
    private var walkers: [Walker] = []
    private var random = SeededRandom(seed: 2_024)
    private var looks: [MeshBuilder.Built] = []

    init(parent: SceneGraph.Node) {
        self.parent = SceneGraph.Node(parent: parent, label: "Villagers")
    }

    private func makeLooks(device: MTLDevice) {
        let outfits: [(Paint, Paint, Paint?)] = [
            (.noren, .thatch, .lattice), (.norenRed, .blackWood, nil), (.plasterCream, .thatch, .noren),
            (.momijiOrange, .blackWood, nil), (.sakuraDeep, .darkWood, nil), (.pineMid, .thatch, .lattice),
            (.lanternWhite, .lattice, .norenRed), (.iris, .darkWood, nil),
        ]
        looks = outfits.compactMap { robe, hair, hat in
            let builder = MeshBuilder()
            builder.frustum(robe, from: [0, 0, 0], to: [0, 0.2, 0], radiusA: 0.055, radiusB: 0.035, sides: 6, caps: true)
            builder.box(.blackWood, center: [0, 0.16, 0], size: [0.075, 0.02, 0.075])
            builder.blob(.foxWhite, center: [0, 0.25, 0], scale: SIMD3(repeating: 0.035))
            builder.blob(hair, center: [-0.008, 0.265, 0], scale: [0.034, 0.03, 0.036])
            if let hat {
                builder.cone(hat == .lattice ? .thatch : hat, base: [0, 0.27, 0], tip: [0, 0.32, 0], radius: 0.075, sides: 8, capped: true)
            }
            return builder.build(device: device, label: "Villager")
        }
    }

    func reset(scene: TownScene) {
        parent.removeAllChildren()
        walkers.removeAll()
        if looks.isEmpty {
            makeLooks(device: scene.device)
        }
        let town = scene.town
        let paths = town.grid.cells.indices.filter { cell in
            let ground = town.cells[cell].ground
            return (ground == .path || ground == .gravel) && scene.isWalkable(town.grid.cells[cell].center, from: town.standingHeight(cell))
        }
        let count = min(24, paths.count / 2)
        for index in 0..<count {
            let cell = paths[random.int(paths.count)]
            let position = town.grid.cells[cell].center + SIMD2(random.signed(), random.signed()) * 0.3
            let look = looks[index % looks.count]
            let node = SceneGraph.Node(parent: parent, label: "Villager", content: .mesh(look.mesh, materials: scene.materials(for: look), castsShadow: true, receivesShadow: true))
            walkers.append(Walker(node: node, position: position, target: position, heading: random.range(0, 2 * .pi), speed: random.range(0.35, 0.6), pause: random.range(0, 3), phase: random.range(0, 6), recent: [cell]))
        }
        for index in walkers.indices {
            place(&walkers[index], scene: scene)
        }
    }

    // After a time-of-day change the materials are new.
    func refreshMaterials(scene: TownScene) {
        for (index, walker) in walkers.enumerated() {
            let look = looks[index % looks.count]
            walker.node.content = .mesh(look.mesh, materials: scene.materials(for: look), castsShadow: true, receivesShadow: true)
        }
    }

    func advance(by deltaTime: Float, scene: TownScene) {
        let town = scene.town
        for index in walkers.indices {
            var walker = walkers[index]
            defer { walkers[index] = walker }
            let here = town.standingHeight(town.grid.cell(at: walker.position) ?? 0)
            guard scene.isWalkable(walker.position, from: here) else {
                // The town changed under them: hop back onto a path.
                walker.pause = 1
                if let cell = town.grid.cells.indices.first(where: { town.cells[$0].ground == .path && scene.isWalkable(town.grid.cells[$0].center, from: town.standingHeight($0)) }) {
                    walker.position = town.grid.cells[cell].center
                    walker.target = walker.position
                } else {
                    walker.node.isVisible = false
                }
                continue
            }
            walker.node.isVisible = true
            if walker.pause > 0 {
                walker.pause -= deltaTime
                place(&walker, scene: scene)
                continue
            }
            let delta = walker.target - walker.position
            if simd_length(delta) < 0.1 {
                chooseTarget(&walker, scene: scene)
                continue
            }
            let step = simd_normalize(delta) * walker.speed * deltaTime
            let next = walker.position + step
            if scene.isWalkable(next, from: here) {
                walker.position = next
                walker.phase += deltaTime * 9
                let desired = atan2(step.x, step.y)
                var turn = desired - walker.heading
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                walker.heading += turn * min(1, deltaTime * 6)
            } else {
                chooseTarget(&walker, scene: scene)
            }
            place(&walker, scene: scene)
        }
    }

    private func chooseTarget(_ walker: inout Walker, scene: TownScene) {
        let town = scene.town
        guard let cell = town.grid.cell(at: walker.position) else {
            return
        }
        walker.recent.append(cell)
        if walker.recent.count > 6 {
            walker.recent.removeFirst()
        }
        let here = town.standingHeight(cell)
        let options = town.grid.neighborSet(of: cell).filter { neighbor in
            let ground = town.cells[neighbor].ground
            return (ground == .path || ground == .gravel || ground == .sand || ground == .moss || ground == .grass)
                && scene.isWalkable(town.grid.cells[neighbor].center, from: here)
        }
        let preferred = options.filter { [.path, .gravel].contains(town.cells[$0].ground) && !walker.recent.contains($0) }
        let pool = preferred.isEmpty ? options.filter { !walker.recent.contains($0) } : preferred
        if let next = (pool.isEmpty ? options : pool).randomElement() {
            walker.target = town.grid.cells[next].center + SIMD2(random.signed(), random.signed()) * 0.25
        }
        if random.chance(0.15) {
            walker.pause = random.range(1, 4)
        }
    }

    private func place(_ walker: inout Walker, scene: TownScene) {
        let height = scene.walkHeight(at: walker.position) ?? 0
        let bob = walker.pause > 0 ? 0 : abs(sin(walker.phase)) * 0.012
        walker.node.trs = Transform3D(translation: walker.position.lifted(height + bob), rotation: simd_quatf(angle: walker.heading, axis: [0, 1, 0]), scale: SIMD3(repeating: 1.7))
    }
}
