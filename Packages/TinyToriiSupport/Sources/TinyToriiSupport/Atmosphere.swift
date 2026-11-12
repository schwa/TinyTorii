import GeometryLite3D
import MetalSprocketsParticles
import SceneSprockets
import simd

// Petals drifting from cherry trees, and fireflies after dark. For looks only.
@MainActor
final class Atmosphere {
    private let node: SceneGraph.Node
    private var petalSpots: [SIMD3<Float>] = []
    private var hasFireflies = false

    init(parent: SceneGraph.Node) {
        node = SceneGraph.Node(parent: parent, label: "Atmosphere")
    }

    func update(town: Town, time: TimeOfDay) {
        var spots: [SIMD3<Float>] = []
        for (cell, state) in town.cells.enumerated() where state.item?.kind == .sakura || state.item?.kind == .ume {
            let level = Float(state.item?.level ?? 1)
            spots.append(town.grid.cells[cell].center.lifted(town.standingHeight(cell) + 2.1 + level * 0.875))
        }
        // A few, spread out.
        var chosen: [SIMD3<Float>] = []
        while chosen.count < 8, !spots.isEmpty {
            let index = spots.indices.max { a, b in
                (chosen.map { simd_distance($0, spots[a]) }.min() ?? .infinity) < (chosen.map { simd_distance($0, spots[b]) }.min() ?? .infinity)
            }!
            chosen.append(spots.remove(at: index))
        }
        let fireflies = time == .night || time == .dusk
        guard chosen != petalSpots || fireflies != hasFireflies else {
            return
        }
        petalSpots = chosen
        hasFireflies = fireflies
        node.removeAllChildren()
        // One system with an emitter per tree: each system is its own simulate pass and draw.
        if !chosen.isEmpty {
            // A point cache of jittered spots under every canopy, so one emitter covers all the trees.
            var random = SeededRandom(seed: 31)
            var points: [EmitterPoint] = []
            for spot in chosen {
                for _ in 0..<32 {
                    points.append(EmitterPoint(spot + SIMD3(random.signed() * 2.45, random.signed() * 0.875, random.signed() * 2.45)))
                }
            }
            var emitter = EmitterDescription("Petals", sprite: .confetti, capacity: 120 * chosen.count) {
                ShapeModule(shape: .points)
                RateModule(birthRate: 4 * Float(chosen.count), warmupDuration: 6)
                LifetimeModule(range: 5...8)
                VelocityModule(velocity: [0.875, -0.42, 0.28], spread: 0.6, speedVariation: 0.5)
                GravityModule(acceleration: [0.14, -0.21, 0])
                DragModule(amount: 0.6)
                RotationModule(angleVariation: .pi, angularSpeed: 2.5, angularSpeedVariation: 2)
                SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.05, 0.21), .init(0.9, 0.21), .init(1, 0)]))
                ColorOverLifeModule(color: .constant([1, 0.78, 0.86, 1]))
                SpriteModule(blendMode: .alpha, orientation: .tumbling)
            }
            emitter.points = points
            let petals = ParticleSystem("Petals") {
                emitter
            }
            let holder = SceneGraph.Node(parent: node, label: "Petals")
            holder.particleSystems = [SceneParticleSystem(petals, seed: 1)]
        }
        if fireflies {
            let radius = town.grid.radius
            let system = ParticleSystem("Fireflies") {
                EmitterDescription("Motes", capacity: 500) {
                    ShapeModule(shape: .box(size: [radius * 1.6, 4.2, radius * 1.6]))
                    RateModule(birthRate: 30, warmupDuration: 10)
                    LifetimeModule(range: 4...8)
                    VelocityModule(velocity: [0, 0.175, 0], spread: 1, speedVariation: 0.8)
                    GravityModule(acceleration: .zero)
                    DragModule(amount: 0.2)
                    SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.3, 0.245), .init(0.7, 0.245), .init(1, 0)]))
                    ColorOverLifeModule(color: .constant([1, 0.85, 0.35, 1]))
                    SpriteModule(blendMode: .additive)
                }
            }
            let holder = SceneGraph.Node(parent: node, label: "Fireflies")
            holder.trs = Transform3D(translation: [0, 3.15, 0])
            holder.particleSystems = [SceneParticleSystem(system, seed: 77)]
        }
    }
}
