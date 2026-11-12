import ModelScript
import simd

// Small things, built in local space: origin on the ground at the cell center, rotated by the item's rotation.
// `polygon` is the cell outline in the same local space; `joined[i]` says whether edge i borders the same kind.
enum PropMesher {
    static func build(_ builder: MeshBuilder, item: Item, polygon: [SIMD2<Float>], joined: [Bool]) {
        var random = SeededRandom(seed: item.seed)
        switch item.kind {
        case .torii:
            let paints = toriiPaints(style: item.style)
            let count = item.level
            let spacing: Float = 1.26
            for index in 0..<count {
                let z = (Float(index) - Float(count - 1) / 2) * spacing
                torii(builder, at: [0, 0, z], width: 2.625, height: 3.5, thickness: 0.21, paints: paints, random: &random)
            }
        case .greatTorii:
            greatTorii(builder, style: item.style)
        case .foxStatue:
            let paint: Paint = [.foxWhite, .foxStone, .bronze][item.style]
            let count = item.level
            for index in 0..<count {
                let angle = Float(index) / Float(count) * 2 * .pi
                let position: SIMD3<Float> = count == 1 ? .zero : [cos(angle) * 1.575, 0, sin(angle) * 1.575]
                fox(builder, at: position, facing: angle + .pi, paint: paint, random: &random)
            }
        case .stoneLantern:
            let count = item.level
            for index in 0..<count {
                let angle = Float(index) / Float(count) * 2 * .pi + 0.4
                let position: SIMD3<Float> = count == 1 ? .zero : [cos(angle) * 1.75, 0, sin(angle) * 1.75]
                stoneLantern(builder, at: position, style: item.style)
            }
        case .paperLantern:
            paperLanterns(builder, style: item.style, level: item.level)
        case .bellTower:
            let parameters: [String: ModelParameter] = [
                "POSTS": ModelLibrary.hex(item.style == 0 ? .vermilion : .darkWood),
                "ROOF": ModelLibrary.hex(item.style == 0 ? .tileGrey : .shingle),
            ]
            do {
                builder.append(try ModelLibrary.compile("bell-tower", parameters: parameters))
            } catch {
                assertionFailure("bell-tower.json: \(error)")
            }
        case .zenGarden:
            // Raked circles around a few rocks.
            let rocks = item.level + 1
            for index in 0..<rocks {
                let angle = random.range(0, 2 * .pi)
                let distance = index == 0 ? 0 : random.range(1.05, 1.925)
                let center = SIMD3<Float>(cos(angle) * distance, 0, sin(angle) * distance)
                let size = random.range(0.42, 0.91) * (index == 0 ? 1.4 : 1)
                for ring in 1...3 {
                    let radius = size * 0.9 + Float(ring) * 0.245
                    ringLine(builder, center: center + [0, 0.035, 0], radius: radius, paint: .gravelLine)
                }
                builder.blob(item.style == 2 ? .moss : .stone, center: center + [0, 0.07, 0], scale: [size * 1.4, size * 0.4, size * 1.4])
                builder.blob(.stoneDark, center: center + [0, size * 0.45, 0], scale: [size, size * 1.1, size * 0.85], rotation: simd_quatf(angle: random.range(0, 6), axis: simd_normalize([random.signed(), 3, random.signed()])))
            }
        case .koiPond:
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: 8, margin: 0.95, random: &random) {
                builder.blob(.stone, center: point.lifted(0.07), scale: [0.49, 0.35, 0.42] * random.range(0.8, 1.3), rotation: simd_quatf(angle: random.range(0, 6), axis: [0, 1, 0]))
            }
            for _ in 0..<(3 + random.int(3)) {
                let angle = random.range(0, 2 * .pi)
                let distance = random.range(0, 1.575)
                let position = SIMD3<Float>(cos(angle) * distance, -0.7525, sin(angle) * distance)
                let heading = random.range(0, 2 * .pi)
                let rotation = simd_quatf(angle: heading, axis: [0, 1, 0])
                builder.blob(random.chance(0.6) ? .koiOrange : .koiWhite, center: position, scale: [0.12, 0.03, 0.045], rotation: rotation)
                builder.blob(.koiOrange, center: position + rotation.act([-0.42, 0, 0]), scale: [0.14, 0.07, 0.14])
            }
            switch item.style {
            case 0:
                for point in GroundMesher.scatter(points: polygon, center: .zero, count: 4, margin: 0.6, random: &random) {
                    builder.disc(.lily, center: point.lifted(-0.7), radius: 0.385, sides: 7)
                    if random.chance(0.5) {
                        builder.blob(.lotus, center: point.lifted(-0.56), scale: [0.175, 0.14, 0.175])
                    }
                }
            case 2:
                for point in GroundMesher.scatter(points: polygon, center: .zero, count: 6, margin: 0.85, random: &random) {
                    for _ in 0..<3 {
                        builder.cone(.lily, base: point.lifted(-0.7), tip: point.lifted(0.875) + [random.signed() * 0.28, 0, random.signed() * 0.28], radius: 0.0875, sides: 3)
                    }
                    builder.blob(.iris, center: point.lifted(0.77), scale: SIMD3(repeating: 0.14))
                }
            default:
                builder.blob(.stoneDark, center: [0.35, -0.35, 0], scale: [0.875, 1.05, 0.7])
            }
        case .bridge:
            let paint: Paint = [.vermilion, .cedar, .stone][item.style]
            let deck: Paint = item.style == 2 ? .stoneLight : .lightWood
            let length: Float = 6.65
            let steps = 12
            func arch(_ t: Float) -> Float { 1.47 * sin(t * .pi) + 0.14 }
            for step in 0..<steps {
                let t0 = Float(step) / Float(steps), t1 = Float(step + 1) / Float(steps)
                let x0 = -length / 2 + t0 * length, x1 = -length / 2 + t1 * length
                let y0 = arch(t0), y1 = arch(t1)
                builder.quad(deck, [x0, y0, -1.05], [x1, y1, -1.05], [x1, y1, 1.05], [x0, y0, 1.05], outwardFrom: [(x0 + x1) / 2, (y0 + y1) / 2 - 3.5, 0])
                builder.quad(paint, [x0, y0, -1.05], [x1, y1, -1.05], [x1, y1 - 0.21, -1.05], [x0, y0 - 0.21, -1.05], outwardFrom: [(x0 + x1) / 2, (y0 + y1) / 2, 0])
                builder.quad(paint, [x0, y0, 1.05], [x1, y1, 1.05], [x1, y1 - 0.21, 1.05], [x0, y0 - 0.21, 1.05], outwardFrom: [(x0 + x1) / 2, (y0 + y1) / 2, 0])
                for z: Float in [-0.98, 0.98] {
                    builder.beam(paint, from: [x0, y0 + 0.91, z], to: [x1, y1 + 0.91, z], width: 0.14, height: 0.14)
                    if step % 3 == 0 {
                        builder.box(paint, center: [x0, y0 + 0.455, z], size: [0.175, 0.91, 0.175])
                    }
                }
            }
            for z: Float in [-0.98, 0.98] {
                for x: Float in [-length / 2, length / 2] {
                    builder.box(paint, center: [x, 0.595, z], size: [0.21, 1.05, 0.21])
                    if item.style == 0 {
                        builder.blob(.gold, center: [x, 1.26, z], scale: SIMD3(repeating: 0.14))
                    }
                }
            }
        case .well:
            let parameters: [String: ModelParameter] = [
                "WALL": ModelLibrary.hex(item.style == 0 ? .stone : .cedar),
                "LID": ModelLibrary.hex(item.style == 0 ? .stoneLight : .lightWood),
            ]
            do {
                builder.append(try ModelLibrary.compile("well", parameters: parameters))
            } catch {
                assertionFailure("well.json: \(error)")
            }
        case .bambooFence:
            let paint: Paint = [.bamboo, .bambooDry, .bambooDry][item.style]
            let tie: Paint = item.style == 2 ? .twine : .darkWood
            for index in polygon.indices where !joined[index] {
                let a = polygon[index] * 0.94, b = polygon[(index + 1) % polygon.count] * 0.94
                let length = simd_distance(a, b)
                let posts = max(2, Int(length / 0.42))
                for post in 0...posts {
                    let point = a + (b - a) * (Float(post) / Float(posts))
                    builder.cylinder(paint, from: point.lifted(0), to: point.lifted(1.925 + (post % 2 == 0 ? 0.14 : 0)), radius: 0.077, sides: 5)
                }
                for y: Float in [0.525, 1.47] {
                    builder.beam(tie, from: a.lifted(y), to: b.lifted(y), width: 0.14, height: 0.105)
                }
            }
        case .azalea:
            let paint: Paint = [.azaleaMagenta, .azaleaPink, .azaleaWhite, .hydrangea][item.style]
            let count = 1 + item.level
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: count, margin: 0.55, random: &random) {
                let size = random.range(0.98, 1.4)
                builder.blob(.leafDark, center: point.lifted(size * 0.5), scale: [size, size * 0.7, size])
                for _ in 0..<10 {
                    let direction = simd_normalize(SIMD3<Float>(random.signed(), random.range(0.1, 1), random.signed()))
                    builder.blob(paint, center: point.lifted(size * 0.5) + direction * [size, size * 0.7, size] * 0.95, scale: SIMD3(repeating: 0.21))
                }
            }
        case .tanuki where item.style == 1:
            Creatures.tanukiStatue(builder)
        case .stones:
            if item.style == 2 {
                // Stacked stones.
                var y: Float = 0
                for index in 0..<(2 + item.level) {
                    let size = 0.77 - Float(index) * 0.105
                    builder.blob(.stone, center: [0, y + size * 0.4, 0], scale: [size, size * 0.45, size], rotation: simd_quatf(angle: random.range(0, 6), axis: [0, 1, 0]))
                    y += size * 0.8
                }
            } else {
                for point in GroundMesher.scatter(points: polygon, center: .zero, count: item.level + 1, margin: 0.6, random: &random) {
                    let size = random.range(0.98, 1.75)
                    builder.blob(item.style == 0 ? .stone : .stoneLight, center: point.lifted(size * 0.3), scale: [size, size * 0.7, size * 0.85], rotation: simd_quatf(angle: random.range(0, 6), axis: simd_normalize([random.signed(), 2, random.signed()])))
                    if item.style == 0 {
                        builder.blob(.moss, center: point.lifted(size * 0.62), scale: [size * 0.7, size * 0.18, size * 0.6])
                    }
                }
            }
        default:
            break
        }
    }

    struct ToriiPaints {
        var post: Paint
        var top: Paint
        var plaque: Paint
    }

    static func toriiPaints(style: Int) -> ToriiPaints {
        switch style {
        case 1: ToriiPaints(post: .stone, top: .stone, plaque: .stoneDark)
        case 2: ToriiPaints(post: .blackWood, top: .blackWood, plaque: .gold)
        case 3: ToriiPaints(post: .vermilion, top: .blackWood, plaque: .blackWood)
        default: ToriiPaints(post: .vermilion, top: .blackWood, plaque: .blackWood)
        }
    }

    // Parameters for Models/torii.json.
    static func toriiParameters(width: Float, height: Float, thickness: Float, paints: ToriiPaints) -> [String: ModelParameter] {
        [
            "WIDTH": .number(Double(width)), "HEIGHT": .number(Double(height)), "THICKNESS": .number(Double(thickness)),
            "POST": ModelLibrary.hex(paints.post), "TOP": ModelLibrary.hex(paints.top), "PLAQUE": ModelLibrary.hex(paints.plaque),
        ]
    }

    // Parameters for Models/great-torii.json. Style 2 is Itsukushima's: vermilion with braced legs.
    // Parameters for Models/paper-lantern.json: 2 + level lanterns, colored in turn from the style's paints.
    static func paperLanternParameters(style: Int, level: Int) -> [String: ModelParameter] {
        let paint: [Paint] = switch style {
        case 1: [.lanternWhite]
        case 2: [.lanternRed, .lanternWhite, .lanternYellow]
        default: [.lanternRed]
        }
        let count = 2 + level
        var parameters: [String: ModelParameter] = ["HEIGHT": .number(4.2 + Double(level) * 0.525), "COUNT": .number(Double(count))]
        for row in 0..<3 {
            parameters["ROW\(row)"] = .number(Double(max(0, (count - row + 2) / 3)))
            parameters["LANTERN\(row)"] = ModelLibrary.hex(paint[row % paint.count])
        }
        return parameters
    }

    // Two poles with a rope of lanterns between them.
    static func paperLanterns(_ builder: MeshBuilder, style: Int, level: Int) {
        do {
            builder.append(try ModelLibrary.compile("paper-lantern", parameters: paperLanternParameters(style: style, level: level)))
        } catch {
            assertionFailure("paper-lantern.json: \(error)")
        }
    }

    static func greatToriiParameters(style: Int) -> [String: ModelParameter] {
        let paints = toriiPaints(style: style == 2 ? 0 : style)
        return [
            "BRACED": .number(style == 2 ? 1 : 0),
            "POST": ModelLibrary.hex(paints.post), "TOP": ModelLibrary.hex(paints.top), "PLAQUE": ModelLibrary.hex(paints.plaque),
        ]
    }

    static func greatTorii(_ builder: MeshBuilder, style: Int) {
        do {
            builder.append(try ModelLibrary.compile("great-torii", parameters: greatToriiParameters(style: style)))
        } catch {
            assertionFailure("great-torii.json: \(error)")
        }
    }

    static func torii(_ builder: MeshBuilder, at origin: SIMD3<Float>, width: Float, height: Float, thickness: Float, paints: ToriiPaints, random: inout SeededRandom) {
        let previous = builder.transform
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(origin, 1)
        builder.setTransform(previous * translation)
        do {
            builder.append(try ModelLibrary.compile("torii", parameters: toriiParameters(width: width, height: height, thickness: thickness, paints: paints)))
        } catch {
            assertionFailure("torii.json: \(error)")
        }
        builder.setTransform(previous)
    }

    static func fox(_ builder: MeshBuilder, at origin: SIMD3<Float>, facing angle: Float, paint: Paint, random: inout SeededRandom) {
        let previous = builder.transform
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(origin, 1)
        let rotation = simd_float4x4(simd_quatf(angle: -angle, axis: [0, 1, 0]))
        builder.setTransform(previous * transform * rotation)
        do {
            builder.append(try ModelLibrary.compile("fox-statue", parameters: ["STATUE": ModelLibrary.hex(paint)]))
        } catch {
            assertionFailure("fox-statue.json: \(error)")
        }
        builder.setTransform(previous)
    }

    // Kasuga lantern on a post, or (style 1) a yukimi lantern on short legs; style 2 is bronze.
    static func stoneLantern(_ builder: MeshBuilder, at origin: SIMD3<Float>, style: Int) {
        let stone: Paint = style == 2 ? .bronze : .stone
        let previous = builder.transform
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(origin, 1)
        builder.setTransform(previous * translation)
        do {
            builder.append(try ModelLibrary.compile("stone-lantern", parameters: ["STYLE": .number(Double(style)), "STONE": ModelLibrary.hex(stone)]))
        } catch {
            assertionFailure("stone-lantern.json: \(error)")
        }
        builder.setTransform(previous)
    }

    static func ring(radius: Float, y: Float, sides: Int) -> [SIMD3<Float>] {
        (0..<sides).map { index in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return [cos(angle) * radius, y, sin(angle) * radius]
        }
    }

    static func ringLine(_ builder: MeshBuilder, center: SIMD3<Float>, radius: Float, paint: Paint) {
        let points = ring(radius: radius, y: 0, sides: 14).map { $0 + center }
        for index in points.indices {
            builder.beam(paint, from: points[index], to: points[(index + 1) % points.count], width: 0.0875, height: 0.035)
        }
    }
}
