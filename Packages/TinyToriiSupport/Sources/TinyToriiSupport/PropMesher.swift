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
            zenGarden(builder, item: item, random: &random)
        case .koiPond:
            koiPond(builder, item: item, polygon: polygon, random: &random)
        case .bridge:
            let paint: Paint = [.vermilion, .cedar, .stone][item.style]
            let deck: Paint = item.style == 2 ? .stoneLight : .lightWood
            let parameters: [String: ModelParameter] = ["STYLE": .number(Double(item.style)), "PAINT": ModelLibrary.hex(paint), "DECK": ModelLibrary.hex(deck)]
            do {
                builder.append(try ModelLibrary.compile("bridge", parameters: parameters))
            } catch {
                assertionFailure("bridge.json: \(error)")
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
            var bushes: (x: [Double], z: [Double], size: [Double]) = ([], [], [])
            var flowers: (x: [Double], y: [Double], z: [Double]) = ([], [], [])
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: count, margin: 0.55, random: &random) {
                let size = random.range(0.98, 1.4)
                bushes.x.append(Double(point.x))
                bushes.z.append(Double(point.y))
                bushes.size.append(Double(size))
                for _ in 0..<10 {
                    let direction = simd_normalize(SIMD3<Float>(random.signed(), random.range(0.1, 1), random.signed()))
                    let flower = point.lifted(size * 0.5) + direction * [size, size * 0.7, size] * 0.95
                    flowers.x.append(Double(flower.x))
                    flowers.y.append(Double(flower.y))
                    flowers.z.append(Double(flower.z))
                }
            }
            let parameters: [String: ModelParameter] = [
                "FLOWER": ModelLibrary.hex(paint),
                "BX": .numbers(bushes.x), "BZ": .numbers(bushes.z), "BS": .numbers(bushes.size),
                "FX": .numbers(flowers.x), "FY": .numbers(flowers.y), "FZ": .numbers(flowers.z),
            ]
            do {
                builder.append(try ModelLibrary.compile("azalea", parameters: parameters))
            } catch {
                assertionFailure("azalea.json: \(error)")
            }
        case .tanuki where item.style == 1:
            Creatures.tanukiStatue(builder)
        case .stones:
            stones(builder, item: item, polygon: polygon, random: &random)
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


    // Raked circles around a few rocks; the seed places them and zen-garden.json draws them.
    static func zenGarden(_ builder: MeshBuilder, item: Item, random: inout SeededRandom) {
        var x: [Double] = [], z: [Double] = [], sizes: [Double] = []
        var turns: [SIMD3<Float>] = []
        for index in 0...item.level {
            let angle = random.range(0, 2 * .pi)
            let distance = index == 0 ? 0 : random.range(1.05, 1.925)
            x.append(Double(cos(angle) * distance))
            z.append(Double(sin(angle) * distance))
            sizes.append(Double(random.range(0.42, 0.91) * (index == 0 ? 1.4 : 1)))
            let turn = simd_quatf(angle: random.range(0, 6), axis: simd_normalize([random.signed(), 3, random.signed()]))
            turns.append(eulerXYZ(turn) * 180 / .pi)
        }
        let parameters: [String: ModelParameter] = [
            "BASE": ModelLibrary.hex(item.style == 2 ? .moss : .stone),
            "X": .numbers(x), "Z": .numbers(z), "SIZE": .numbers(sizes),
            "RX": .numbers(turns.map { Double($0.x) }), "RY": .numbers(turns.map { Double($0.y) }), "RZ": .numbers(turns.map { Double($0.z) }),
        ]
        do {
            builder.append(try ModelLibrary.compile("zen-garden", parameters: parameters))
        } catch {
            assertionFailure("zen-garden.json: \(error)")
        }
    }

    // Edge stones, koi, and lilies or reeds; the seed and cell outline place them and koi-pond.json draws them.
    static func koiPond(_ builder: MeshBuilder, item: Item, polygon: [SIMD2<Float>], random: inout SeededRandom) {
        var lists: [String: [Float]] = [:]
        func add(_ name: String, _ value: Float) {
            lists[name, default: []].append(value)
        }
        let degree: Float = 180 / .pi
        for name in ["SX", "SZ", "SK", "SA", "KX", "KZ", "KH", "KW", "TX", "TZ", "LX", "LZ", "LOTUS", "CX", "CY", "CZ", "CL", "CA", "CB", "CC", "IX", "IZ"] {
            lists[name] = []
        }
        for point in GroundMesher.scatter(points: polygon, center: .zero, count: 8, margin: 0.95, random: &random) {
            add("SX", point.x)
            add("SZ", point.y)
            add("SK", random.range(0.8, 1.3))
            add("SA", random.range(0, 6) * degree)
        }
        for _ in 0..<(3 + random.int(3)) {
            let angle = random.range(0, 2 * .pi)
            let distance = random.range(0, 1.575)
            let heading = random.range(0, 2 * .pi)
            let tail = simd_quatf(angle: heading, axis: [0, 1, 0]).act([-0.42, 0, 0])
            add("KX", cos(angle) * distance)
            add("KZ", sin(angle) * distance)
            add("KH", heading * degree)
            add("KW", random.chance(0.6) ? 0 : 1)
            add("TX", cos(angle) * distance + tail.x)
            add("TZ", sin(angle) * distance + tail.z)
        }
        switch item.style {
        case 0:
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: 4, margin: 0.6, random: &random) {
                add("LX", point.x)
                add("LZ", point.y)
                add("LOTUS", random.chance(0.5) ? 1 : 0)
            }
        case 2:
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: 6, margin: 0.85, random: &random) {
                for _ in 0..<3 {
                    let base = point.lifted(-0.7)
                    let tip = point.lifted(0.875) + [random.signed() * 0.28, 0, random.signed() * 0.28]
                    let center = (base + tip) / 2
                    let turn = eulerXYZ(coneFrame(axis: simd_normalize(tip - base))) * degree
                    add("CX", center.x)
                    add("CY", center.y)
                    add("CZ", center.z)
                    add("CL", simd_distance(base, tip))
                    add("CA", turn.x)
                    add("CB", turn.y)
                    add("CC", turn.z)
                }
                add("IX", point.x)
                add("IZ", point.y)
            }
        default:
            break
        }
        var parameters: [String: ModelParameter] = ["STYLE": .number(Double(item.style))]
        for (name, values) in lists {
            parameters[name] = .numbers(values.map(Double.init))
        }
        do {
            builder.append(try ModelLibrary.compile("koi-pond", parameters: parameters))
        } catch {
            assertionFailure("koi-pond.json: \(error)")
        }
    }

    // A stack of stones (style 2) or scattered rocks; the seed places them and stones.json draws them.
    static func stones(_ builder: MeshBuilder, item: Item, polygon: [SIMD2<Float>], random: inout SeededRandom) {
        let degree: Float = 180 / .pi
        var x: [Double] = [], z: [Double] = [], sizes: [Double] = []
        var turns: [SIMD3<Float>] = []
        if item.style == 2 {
            for _ in 0..<(2 + item.level) {
                turns.append([0, random.range(0, 6) * degree, 0])
            }
        } else {
            for point in GroundMesher.scatter(points: polygon, center: .zero, count: item.level + 1, margin: 0.6, random: &random) {
                x.append(Double(point.x))
                z.append(Double(point.y))
                sizes.append(Double(random.range(0.98, 1.75)))
                let turn = simd_quatf(angle: random.range(0, 6), axis: simd_normalize([random.signed(), 2, random.signed()]))
                turns.append(eulerXYZ(turn) * degree)
            }
        }
        let parameters: [String: ModelParameter] = [
            "STYLE": .number(Double(item.style)),
            "ROCK": ModelLibrary.hex(item.style == 1 ? .stoneLight : .stone),
            "X": .numbers(x), "Z": .numbers(z), "S": .numbers(sizes),
            "RX": .numbers(turns.map { Double($0.x) }), "RY": .numbers(turns.map { Double($0.y) }), "RZ": .numbers(turns.map { Double($0.z) }),
        ]
        do {
            builder.append(try ModelLibrary.compile("stones", parameters: parameters))
        } catch {
            assertionFailure("stones.json: \(error)")
        }
    }

    // The turn that stands a ModelScript cone (apex up +y, first corner toward +z) along `axis` with its first
    // corner where MeshBuilder.cone puts it.
    static func coneFrame(axis: SIMD3<Float>) -> simd_float3x3 {
        let reference: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, reference))
        let v = simd_cross(axis, u)
        return simd_float3x3(v, axis, u)
    }

    static func eulerXYZ(_ rotation: simd_quatf) -> SIMD3<Float> {
        eulerXYZ(simd_float3x3(rotation))
    }

    // Angles (radians) for ModelScript's "rotate", which turns about x, then y, then z: R = Rx * Ry * Rz.
    static func eulerXYZ(_ m: simd_float3x3) -> SIMD3<Float> {
        // m[column][row]
        let y = asin(max(-1, min(1, m[2][0])))
        let x = atan2(-m[2][1], m[2][2])
        let z = atan2(-m[1][0], m[0][0])
        return [x, y, z]
    }
}
