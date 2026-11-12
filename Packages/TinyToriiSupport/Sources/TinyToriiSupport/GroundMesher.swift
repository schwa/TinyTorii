import simd

enum GroundMesher {
    static let seaLevel: Float = -1.05
    static let seaFloor: Float = -3.15

    static func build(_ builder: MeshBuilder, town: Town, cell: Int) {
        let grid = town.grid
        let state = town.cells[cell]
        let points = grid.polygon(of: cell)
        let center = grid.cells[cell].center
        let top = town.groundHeight(cell)
        var random = SeededRandom(seed: UInt32(cell) &* 2_654_435_761 &+ town.gridSeed)

        let paint: Paint = switch state.ground {
        case .grass: [.grass, .grassLight, .grassDark, .grass][random.int(4)]
        case .moss: .moss
        case .gravel: .gravel
        case .path: .path
        case .sand: .sand
        case .water: .water
        case .paddy: .paddyWater
        }

        // Top with a small bevel, so the organic grid shows as soft seams.
        let bevel: Float = 0.175
        func inset(_ point: SIMD2<Float>, _ distance: Float) -> SIMD2<Float> {
            let direction = point - center
            let length = simd_length(direction)
            return length > distance * 2 ? point - direction / length * distance : point
        }
        let inner = points.map { inset($0, 0.245).lifted(top) }
        builder.cap(paint, inner)
        let rim: Paint = state.ground == .water ? .stone : (state.ground == .grass ? .grassDark : paint)
        for index in points.indices {
            let next = (index + 1) % points.count
            let outerA = points[index].lifted(top - bevel), outerB = points[next].lifted(top - bevel)
            builder.quad(rim, inner[index], inner[next], outerB, outerA, outwardFrom: center.lifted(top - 10))
        }

        // Sides wherever the neighbor is lower, down to its top (or the sea floor).
        for index in points.indices {
            let neighbor = grid.cells[cell].neighbors[index]
            let bottom = neighbor.map { town.groundHeight($0) - 0.175 } ?? seaFloor
            guard bottom < top - bevel - 0.0035 else {
                continue
            }
            let next = (index + 1) % points.count
            let a = points[index], b = points[next]
            let side: Paint = state.elevation > 0 ? .cliff : (neighbor == nil ? .sand : (neighbor.map { town.cells[$0].ground == .water } == true ? .stoneDark : .soil))
            builder.quad(side, a.lifted(bottom), b.lifted(bottom), b.lifted(top - bevel), a.lifted(top - bevel), outwardFrom: center.lifted(top - 0.7))
            if state.elevation > 0 {
                // Stone courses on raised ground.
                var y = top - bevel - 0.63
                while y > bottom + 0.175 {
                    let normal = simd_normalize((b - a).perpendicular) * (simd_dot((b - a).perpendicular, (a + b) / 2 - center) > 0 ? 1 : -1)
                    builder.beam(.stoneDark, from: (a + normal * 0.035).lifted(y), to: (b + normal * 0.035).lifted(y), width: 0.0525, height: 0.0875)
                    y -= 0.7
                }
            }
        }

        if let item = state.item, item.kind.isBuilding {
            return
        }
        let hasItem = state.item != nil
        decorate(builder, ground: state.ground, points: points, center: center, top: top, hasItem: hasItem, random: &random)
    }

    // Random points inside a polygon, by rejection against its triangles from the center.
    static func scatter(points: [SIMD2<Float>], center: SIMD2<Float>, count: Int, margin: Float = 0.75, random: inout SeededRandom) -> [SIMD2<Float>] {
        (0..<count).map { _ in
            let index = random.int(points.count)
            let a = points[index], b = points[(index + 1) % points.count]
            var u = random.next(), v = random.next()
            if u + v > 1 {
                u = 1 - u
                v = 1 - v
            }
            let point = center + ((a - center) * u + (b - center) * v)
            return center + (point - center) * margin
        }
    }

    private static func decorate(_ builder: MeshBuilder, ground: Ground, points: [SIMD2<Float>], center: SIMD2<Float>, top: Float, hasItem: Bool, random: inout SeededRandom) {
        switch ground {
        case .grass:
            let count = hasItem ? 2 : 5
            for point in scatter(points: points, center: center, count: count, random: &random) {
                let height = random.range(0.175, 0.35)
                builder.cone(.grassDark, base: point.lifted(top), tip: point.lifted(top + height) + [random.signed() * 0.07, 0, random.signed() * 0.07], radius: 0.105, sides: 3)
            }
            if !hasItem, random.chance(0.25) {
                let flower: Paint = random.pick([.azaleaWhite, .ginkgoYellow, .azaleaPink, .hydrangea])
                for point in scatter(points: points, center: center, count: 4, random: &random) {
                    builder.blob(flower, center: point.lifted(top + 0.175), scale: SIMD3(repeating: 0.1225))
                }
            }
        case .moss:
            for point in scatter(points: points, center: center, count: 6, random: &random) {
                builder.blob(random.chance(0.5) ? .moss : .grassDark, center: point.lifted(top), scale: [0.56, 0.175, 0.56] * random.range(0.6, 1.3))
            }
        case .gravel:
            guard !hasItem else {
                return
            }
            for ring in 1...3 {
                let scale = 0.88 - Float(ring) * 0.2
                let ringPoints = points.map { center + ($0 - center) * scale }
                for index in ringPoints.indices {
                    let a = ringPoints[index], b = ringPoints[(index + 1) % ringPoints.count]
                    builder.beam(.gravelLine, from: a.lifted(top + 0.0175), to: b.lifted(top + 0.0175), width: 0.105, height: 0.035)
                }
            }
        case .path:
            for point in scatter(points: points, center: center, count: 4, margin: 0.6, random: &random) {
                builder.blob(.stoneLight, center: point.lifted(top), scale: [0.7, 0.105, 0.56] * random.range(0.8, 1.2), rotation: simd_quatf(angle: random.range(0, 3), axis: [0, 1, 0]))
            }
        case .sand:
            if !hasItem, random.chance(0.3) {
                builder.blob(.stone, center: center.lifted(top), scale: [1.05, 0.7, 0.875], rotation: simd_quatf(angle: random.range(0, 3), axis: [0, 1, 0]))
            }
        case .water:
            if !hasItem {
                for point in scatter(points: points, center: center, count: 3, margin: 0.6, random: &random) where random.chance(0.6) {
                    builder.disc(.lily, center: point.lifted(top + 0.035), radius: 0.42, sides: 7)
                }
            }
        case .paddy:
            let spacing: Float = 0.84
            let minimum = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let maximum = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            var x = minimum.x
            while x < maximum.x {
                var z = minimum.y
                while z < maximum.y {
                    let point = SIMD2<Float>(x, z)
                    if insidePolygon(point, points.map { center + ($0 - center) * 0.85 }) {
                        builder.cone(.rice, base: point.lifted(top), tip: point.lifted(top + 0.7), radius: 0.1575, sides: 3)
                    }
                    z += spacing
                }
                x += spacing
            }
        }
    }

    static func insidePolygon(_ point: SIMD2<Float>, _ polygon: [SIMD2<Float>]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
