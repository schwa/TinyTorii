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
            spots.append(town.grid.cells[cell].center.lifted(town.standingHeight(cell) + 0.6 + level * 0.25))
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
        for (index, spot) in chosen.enumerated() {
            let petals = ParticleSystem("Petals") {
                EmitterDescription("Petals", sprite: .confetti, capacity: 120) {
                    ShapeModule(shape: .box(size: [1.4, 0.5, 1.4]))
                    RateModule(birthRate: 4, warmupDuration: 6)
                    LifetimeModule(range: 5...8)
                    VelocityModule(velocity: [0.25, -0.12, 0.08], spread: 0.6, speedVariation: 0.5)
                    GravityModule(acceleration: [0.04, -0.06, 0])
                    DragModule(amount: 0.6)
                    RotationModule(angleVariation: .pi, angularSpeed: 2.5, angularSpeedVariation: 2)
                    SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.05, 0.06), .init(0.9, 0.06), .init(1, 0)]))
                    ColorOverLifeModule(color: .constant([1, 0.78, 0.86, 1]))
                    SpriteModule(blendMode: .alpha, orientation: .tumbling)
                }
            }
            let holder = SceneGraph.Node(parent: node, label: "Petals")
            holder.trs = Transform3D(translation: spot)
            holder.particleSystems = [SceneParticleSystem(petals, seed: UInt32(index + 1))]
        }
        if fireflies {
            let radius = town.grid.radius
            let system = ParticleSystem("Fireflies") {
                EmitterDescription("Motes", capacity: 500) {
                    ShapeModule(shape: .box(size: [radius * 1.6, 1.2, radius * 1.6]))
                    RateModule(birthRate: 30, warmupDuration: 10)
                    LifetimeModule(range: 4...8)
                    VelocityModule(velocity: [0, 0.05, 0], spread: 1, speedVariation: 0.8)
                    GravityModule(acceleration: .zero)
                    DragModule(amount: 0.2)
                    SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.3, 0.07), .init(0.7, 0.07), .init(1, 0)]))
                    ColorOverLifeModule(color: .constant([1, 0.85, 0.35, 1]))
                    SpriteModule(blendMode: .additive)
                }
            }
            let holder = SceneGraph.Node(parent: node, label: "Fireflies")
            holder.trs = Transform3D(translation: [0, 0.9, 0])
            holder.particleSystems = [SceneParticleSystem(system, seed: 77)]
        }
    }
}
