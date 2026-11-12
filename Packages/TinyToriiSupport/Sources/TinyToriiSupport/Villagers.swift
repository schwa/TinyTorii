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

    // A sōsaku kokeshi: a turned wooden body with no arms or legs, a big round head, and painted bands. Each look has
    // its own body profile, as creative kokeshi differ from one maker to the next.
    private struct Kokeshi {
        // Body radius at heights from the base to the neck.
        var profile: [(height: Float, radius: Float)]
        var body: Paint
        // Painted rings: height and paint.
        var bands: [(height: Float, paint: Paint)]
        var headRadius: Float
        var hair: Paint
    }

    private static let kokeshi: [Kokeshi] = [
        // Straight column.
        Kokeshi(profile: [(0, 0.042), (0.19, 0.042)], body: .norenRed, bands: [(0.03, .gold), (0.15, .blackWood)], headRadius: 0.05, hair: .blackWood),
        // Widening toward the base.
        Kokeshi(profile: [(0, 0.058), (0.18, 0.03)], body: .noren, bands: [(0.05, .sakura), (0.11, .sakura)], headRadius: 0.048, hair: .blackWood),
        // Pinched waist.
        Kokeshi(profile: [(0, 0.048), (0.09, 0.032), (0.19, 0.044)], body: .plasterCream, bands: [(0.09, .vermilion)], headRadius: 0.052, hair: .darkWood),
        // Widening toward the shoulders.
        Kokeshi(profile: [(0, 0.03), (0.18, 0.05)], body: .momijiOrange, bands: [(0.14, .lanternWhite), (0.06, .blackWood)], headRadius: 0.05, hair: .blackWood),
        // Round belly.
        Kokeshi(profile: [(0, 0.035), (0.07, 0.055), (0.18, 0.034)], body: .sakuraDeep, bands: [(0.07, .lanternWhite)], headRadius: 0.046, hair: .darkWood),
        // Slim and tall.
        Kokeshi(profile: [(0, 0.036), (0.2, 0.03)], body: .pineMid, bands: [(0.04, .gold), (0.1, .gold), (0.16, .gold)], headRadius: 0.044, hair: .blackWood),
        // Bell.
        Kokeshi(profile: [(0, 0.06), (0.05, 0.05), (0.18, 0.032)], body: .lanternWhite, bands: [(0.03, .norenRed), (0.12, .norenRed)], headRadius: 0.05, hair: .blackWood),
        // Short and stout, with a big head.
        Kokeshi(profile: [(0, 0.05), (0.16, 0.045)], body: .iris, bands: [(0.08, .umePink)], headRadius: 0.058, hair: .darkWood),
    ]

    private func makeLooks(device: MTLDevice) {
        looks = Self.kokeshi.compactMap { doll in
            let builder = MeshBuilder()
            let sides = 10
            for (lower, upper) in zip(doll.profile, doll.profile.dropFirst()) {
                builder.frustum(doll.body, from: [0, lower.height, 0], to: [0, upper.height, 0], radiusA: lower.radius, radiusB: upper.radius, sides: sides, caps: true)
            }
            for band in doll.bands {
                // Sit the ring just proud of the body so it reads as paint.
                let radius = Self.radius(of: doll.profile, at: band.height) + 0.002
                builder.frustum(band.paint, from: [0, band.height - 0.008, 0], to: [0, band.height + 0.008, 0], radiusA: radius, radiusB: radius, sides: sides)
            }
            let neck = doll.profile.last!.height
            let head = SIMD3<Float>(0, neck + doll.headRadius * 0.9, 0)
            // A turned head: the face below, a painted hair cap above. The face looks along +x.
            Self.sphere(builder, center: head, radius: doll.headRadius, fromLatitude: -.pi / 2, toLatitude: 0.35, paint: .foxWhite)
            Self.sphere(builder, center: head, radius: doll.headRadius * 1.03, fromLatitude: 0.3, toLatitude: .pi / 2, paint: doll.hair)
            for side: Float in [-1, 1] {
                builder.box(.blackWood, center: head + [doll.headRadius * 0.95, 0.004, side * doll.headRadius * 0.32], size: [0.008, 0.004, 0.012])
            }
            return builder.build(device: device, label: "Villager")
        }
    }

    // A band of a sphere between two latitudes, built from stacked rings.
    private static func sphere(_ builder: MeshBuilder, center: SIMD3<Float>, radius: Float, fromLatitude: Float, toLatitude: Float, paint: Paint) {
        let steps = 5
        for step in 0..<steps {
            let lower = fromLatitude + (toLatitude - fromLatitude) * Float(step) / Float(steps)
            let upper = fromLatitude + (toLatitude - fromLatitude) * Float(step + 1) / Float(steps)
            builder.frustum(paint, from: center + [0, radius * sin(lower), 0], to: center + [0, radius * sin(upper), 0], radiusA: max(0.0005, radius * cos(lower)), radiusB: max(0.0005, radius * cos(upper)), sides: 12, caps: step == steps - 1 && toLatitude < .pi / 2)
        }
    }

    private static func radius(of profile: [(height: Float, radius: Float)], at height: Float) -> Float {
        for (lower, upper) in zip(profile, profile.dropFirst()) where height <= upper.height {
            let fraction = (height - lower.height) / (upper.height - lower.height)
            return lower.radius + (upper.radius - lower.radius) * max(0, min(1, fraction))
        }
        return profile.last!.radius
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
