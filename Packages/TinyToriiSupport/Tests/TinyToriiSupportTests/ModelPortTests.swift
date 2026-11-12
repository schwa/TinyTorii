import Foundation
import simd
import Testing
import ModelScript
@testable import TinyToriiSupport

// Models moved from hand-written Swift to ModelScript files must keep their shape: each paint's bounding box is
// checked against the one the Swift geometry made, recorded before the move. The recordings predate the switch to
// meters (#4), so they are in the old units: `bounds` scales them by `oldUnit`.
@Suite struct ModelPortTests {
    struct Bounds: CustomStringConvertible {
        var min: SIMD3<Float>
        var max: SIMD3<Float>

        var description: String {
            func format(_ v: SIMD3<Float>) -> String {
                "[\(String(format: "%.4f", v.x)), \(String(format: "%.4f", v.y)), \(String(format: "%.4f", v.z))]"
            }
            return "(\(format(min)), \(format(max)))"
        }
    }

    static func paintBounds(_ builder: MeshBuilder) -> [Paint: Bounds] {
        var result: [Paint: Bounds] = [:]
        for (position, coordinate) in zip(builder.positions, builder.coordinates) {
            let paint = Paint.allCases[Int(coordinate.x * Float(Paint.allCases.count))]
            if var bounds = result[paint] {
                bounds.min = simd_min(bounds.min, position)
                bounds.max = simd_max(bounds.max, position)
                result[paint] = bounds
            } else {
                result[paint] = Bounds(min: position, max: position)
            }
        }
        return result
    }

    // Builds a ModelScript model and checks each paint's bounds against the old Swift geometry's.
    static func expect(_ name: String, parameters: [String: ModelParameter], matches expected: [Paint: Bounds], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let builder = MeshBuilder()
        builder.append(try ModelLibrary.compile(name, parameters: parameters))
        let actual = paintBounds(builder)
        #expect(Set(actual.keys) == Set(expected.keys), "\(name) \(parameters) paints", sourceLocation: sourceLocation)
        for (paint, bounds) in expected {
            guard let found = actual[paint] else {
                continue
            }
            let error = max(simd_reduce_max(simd_abs(found.min - bounds.min)), simd_reduce_max(simd_abs(found.max - bounds.max)))
            #expect(error < 0.008 * oldUnit, "\(name) \(parameters) .\(paint): \(found), expected \(bounds)", sourceLocation: sourceLocation)
        }
    }

    // A regular cell outline, for props that scatter things inside their cell.
    static let hexagon: [SIMD2<Float>] = (0..<6).map { index in
        let angle = Float(index) / 6 * 2 * .pi
        return [cos(angle) * 3.675, sin(angle) * 3.675]
    }

    // Builds a placed prop through PropMesher and checks each paint's bounds (in meters).
    static func expectProp(_ item: Item, polygon: [SIMD2<Float>] = [], matches expected: [Paint: Bounds], sourceLocation: SourceLocation = #_sourceLocation) {
        let builder = MeshBuilder()
        PropMesher.build(builder, item: item, polygon: polygon, joined: [])
        let actual = paintBounds(builder)
        #expect(Set(actual.keys) == Set(expected.keys), "\(item) paints", sourceLocation: sourceLocation)
        for (paint, bounds) in expected {
            guard let found = actual[paint] else {
                continue
            }
            let error = max(simd_reduce_max(simd_abs(found.min - bounds.min)), simd_reduce_max(simd_abs(found.max - bounds.max)))
            #expect(error < 0.008 * oldUnit, "\(item.kind) \(item.style) \(item.level) .\(paint): \(found), expected \(bounds)", sourceLocation: sourceLocation)
        }
    }

    // Meters per old unit.
    static let oldUnit: Float = 3.5

    static func bounds(_ min: SIMD3<Float>, _ max: SIMD3<Float>) -> Bounds {
        Bounds(min: min * oldUnit, max: max * oldUnit)
    }

    // Paint.nearest can only find a paint whose color no other paint shares.
    @Test func everyPaintRoundTripsThroughItsColor() {
        for paint in Paint.allCases where paint != .highlight && paint != .highlightStretch {
            #expect(Paint.nearest(to: paint.color) == paint, "\(paint)")
        }
    }

    @Test func bellTower() throws {
        let bronze = Self.bounds([-0.2283, 0.7500, -0.2400], [0.2283, 1.5481, 0.2400])
        let beam = Self.bounds([-0.3800, 1.0650, 0.2650], [0.3800, 1.1350, 0.3350])
        let stone = Self.bounds([-0.5500, 0.0000, -0.5500], [0.5500, 0.2000, 0.5500])
        let roof = Self.bounds([-0.7000, 1.7600, -0.7000], [0.7000, 2.3010, 0.7000])
        try Self.expect("bell-tower", parameters: ["POSTS": ModelLibrary.hex(.vermilion), "ROOF": ModelLibrary.hex(.tileGrey)], matches: [
            .bronze: bronze, .lightWood: beam, .stone: stone, .tileGrey: roof,
            .darkWood: Self.bounds([-0.7000, 1.6200, -0.7000], [0.7000, 1.7600, 0.7000]),
            .vermilion: Self.bounds([-0.4400, 0.2000, -0.4400], [0.4400, 1.7000, 0.4400]),
        ])
        try Self.expect("bell-tower", parameters: ["POSTS": ModelLibrary.hex(.darkWood), "ROOF": ModelLibrary.hex(.shingle)], matches: [
            .bronze: bronze, .lightWood: beam, .stone: stone, .shingle: roof,
            .darkWood: Self.bounds([-0.7000, 0.2000, -0.7000], [0.7000, 1.7600, 0.7000]),
        ])
    }

    // The Swift well's lid was a full disc over the top, so its water and inner wall were never visible; the model
    // leaves them out. The lid's corners on x sit inside the posts, which the union drops (x 0.3 -> 0.2919).
    @Test func well() throws {
        let lid = Self.bounds([-0.2919, 0.3500, -0.2853], [0.2919, 0.3500, 0.2853])
        let darkWood = Self.bounds([-0.4000, 0.2000, -0.4000], [0.4000, 0.9400, 0.4000])
        let shingle = Self.bounds([-0.4000, 0.9400, -0.4000], [0.4000, 1.2310, 0.4000])
        try Self.expect("well", parameters: ["WALL": ModelLibrary.hex(.stone), "LID": ModelLibrary.hex(.stoneLight)], matches: [
            .cedar: Self.bounds([-0.0600, 0.4500, -0.0600], [0.0600, 0.6000, 0.0600]),
            .darkWood: darkWood,
            .shingle: shingle,
            .stone: Self.bounds([-0.2853, 0.0000, -0.3000], [0.2853, 0.3500, 0.3000]),
            .stoneLight: lid,
        ])
        try Self.expect("well", parameters: ["WALL": ModelLibrary.hex(.cedar), "LID": ModelLibrary.hex(.lightWood)], matches: [
            .cedar: Self.bounds([-0.2853, 0.0000, -0.3000], [0.2853, 0.6000, 0.3000]),
            .darkWood: darkWood,
            .lightWood: lid,
            .shingle: shingle,
        ])
    }

    // Indexed by level * 3 + style.
    static let paperLanterns: [[Paint: Bounds]] = [
            [
                .blackWood: bounds([-0.3500, 0.7075, -0.0500], [0.3500, 0.7275, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.2000, 0.0350]),
                .lanternRed: bounds([-0.3766, 0.7269, -0.0766], [0.3766, 0.9481, 0.0766]),
                .twine: bounds([-0.6025, 0.9575, -0.0060], [0.6025, 1.1554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.3500, 0.7075, -0.0500], [0.3500, 0.7275, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.2000, 0.0350]),
                .lanternWhite: bounds([-0.3766, 0.7269, -0.0766], [0.3766, 0.9481, 0.0766]),
                .twine: bounds([-0.6025, 0.9575, -0.0060], [0.6025, 1.1554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.3500, 0.7075, -0.0500], [0.3500, 0.7275, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.2000, 0.0350]),
                .lanternRed: bounds([-0.3766, 0.7269, -0.0766], [-0.2234, 0.9481, 0.0766]),
                .lanternWhite: bounds([0.2234, 0.7269, -0.0766], [0.3766, 0.9481, 0.0766]),
                .twine: bounds([-0.6025, 0.9575, -0.0060], [0.6025, 1.1554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.4500, 0.8200, -0.0500], [0.4500, 0.9067, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.3500, 0.0350]),
                .lanternRed: bounds([-0.4766, 0.8394, -0.0766], [0.4766, 1.1273, 0.0766]),
                .twine: bounds([-0.6025, 1.0700, -0.0060], [0.6025, 1.3054, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.4500, 0.8200, -0.0500], [0.4500, 0.9067, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.3500, 0.0350]),
                .lanternWhite: bounds([-0.4766, 0.8394, -0.0766], [0.4766, 1.1273, 0.0766]),
                .twine: bounds([-0.6025, 1.0700, -0.0060], [0.6025, 1.3054, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.4500, 0.8200, -0.0500], [0.4500, 0.9067, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.3500, 0.0350]),
                .lanternRed: bounds([-0.4766, 0.9061, -0.0766], [-0.3234, 1.1273, 0.0766]),
                .lanternWhite: bounds([-0.0766, 0.8394, -0.0766], [0.0766, 1.0606, 0.0766]),
                .lanternYellow: bounds([0.3234, 0.9061, -0.0766], [0.4766, 1.1273, 0.0766]),
                .twine: bounds([-0.6025, 1.0700, -0.0060], [0.6025, 1.3054, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5000, 0.9794, -0.0500], [0.5000, 1.0744, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.5000, 0.0350]),
                .lanternRed: bounds([-0.5266, 0.9988, -0.0766], [0.5266, 1.2950, 0.0766]),
                .twine: bounds([-0.6025, 1.2294, -0.0060], [0.6025, 1.4554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5000, 0.9794, -0.0500], [0.5000, 1.0744, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.5000, 0.0350]),
                .lanternWhite: bounds([-0.5266, 0.9988, -0.0766], [0.5266, 1.2950, 0.0766]),
                .twine: bounds([-0.6025, 1.2294, -0.0060], [0.6025, 1.4554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5000, 0.9794, -0.0500], [0.5000, 1.0744, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.5000, 0.0350]),
                .lanternRed: bounds([-0.5266, 1.0738, -0.0766], [0.5266, 1.2950, 0.0766]),
                .lanternWhite: bounds([-0.2266, 0.9988, -0.0766], [-0.0734, 1.2200, 0.0766]),
                .lanternYellow: bounds([0.0734, 0.9988, -0.0766], [0.2266, 1.2200, 0.0766]),
                .twine: bounds([-0.6025, 1.2294, -0.0060], [0.6025, 1.4554, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5300, 1.1200, -0.0500], [0.5300, 1.2360, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.6500, 0.0350]),
                .lanternRed: bounds([-0.5566, 1.1394, -0.0766], [0.5566, 1.4566, 0.0766]),
                .twine: bounds([-0.6025, 1.3700, -0.0060], [0.6025, 1.6054, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5300, 1.1200, -0.0500], [0.5300, 1.2360, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.6500, 0.0350]),
                .lanternWhite: bounds([-0.5566, 1.1394, -0.0766], [0.5566, 1.4566, 0.0766]),
                .twine: bounds([-0.6025, 1.3700, -0.0060], [0.6025, 1.6054, 0.0060]),
            ],
            [
                .blackWood: bounds([-0.5300, 1.1200, -0.0500], [0.5300, 1.2360, 0.0500]),
                .darkWood: bounds([-0.6350, 0.0000, -0.0350], [0.6350, 1.6500, 0.0350]),
                .lanternRed: bounds([-0.5566, 1.1634, -0.0766], [0.3166, 1.4566, 0.0766]),
                .lanternWhite: bounds([-0.3166, 1.1634, -0.0766], [0.5566, 1.4566, 0.0766]),
                .lanternYellow: bounds([-0.0766, 1.1394, -0.0766], [0.0766, 1.3606, 0.0766]),
                .twine: bounds([-0.6025, 1.3700, -0.0060], [0.6025, 1.6054, 0.0060]),
            ],
    ]

    @Test(arguments: 0..<4, 0..<3) func paperLanterns(level: Int, style: Int) throws {
        var expected = Self.paperLanterns[level * 3 + style]
        // The union drops the rope's ends inside the poles: it now stops at the pole surface (x 0.5675), where it
        // hangs 0.0146 lower than at the pole's center.
        if let rope = expected[.twine] {
            expected[.twine] = Bounds(min: [-0.5675 * Self.oldUnit, rope.min.y, rope.min.z], max: [0.5675 * Self.oldUnit, rope.max.y - 0.0146 * Self.oldUnit, rope.max.z])
        }
        try Self.expect("paper-lantern", parameters: PropMesher.paperLanternParameters(style: style, level: level), matches: expected)
    }

    @Test func greatTorii() throws {
        let rope = Self.bounds([-0.6500, 1.9250, -0.0250], [0.6500, 1.9750, 0.0250])
        let expected: [[Paint: Bounds]] = [
            [.blackWood: Self.bounds([-1.3940, 0.0000, -0.1040], [1.3940, 2.5560, 0.1040]), .rope: rope, .vermilion: Self.bounds([-1.1050, 0.0000, -0.0975], [1.1050, 2.2568, 0.0960])],
            [.blackWood: Self.bounds([-0.9880, 0.0000, -0.1040], [0.9880, 0.1920, 0.1040]), .rope: rope, .stone: Self.bounds([-1.3940, 0.0000, -0.0975], [1.3940, 2.5560, 0.0960]), .stoneDark: Self.bounds([-0.0910, 1.8000, -0.0325], [0.0910, 2.1360, 0.0325])],
            [.blackWood: Self.bounds([-1.3940, 0.0000, -0.1040], [1.3940, 2.5560, 0.1040]), .rope: rope, .vermilion: Self.bounds([-1.1050, 0.0000, -0.3600], [1.1050, 2.2568, 0.3600])],
        ]
        for (style, bounds) in expected.enumerated() {
            try Self.expect("great-torii", parameters: PropMesher.greatToriiParameters(style: style), matches: bounds)
        }
    }

    @Test func torii() throws {
        let sizes: [(width: Float, height: Float, thickness: Float)] = [(2.625, 3.5, 0.21), (5.95, 8.4, 0.455)]
        let expected: [[[Paint: Bounds]]] = [
            [
                [.blackWood: Self.bounds([-0.6204, 0.0000, -0.0480], [0.6204, 1.0714, 0.0480]), .vermilion: Self.bounds([-0.4875, -0.0007, -0.0450], [0.4875, 0.9425, 0.0450])],
                [.blackWood: Self.bounds([-0.4380, 0.0000, -0.0480], [0.4380, 0.0800, 0.0480]), .stone: Self.bounds([-0.6204, -0.0007, -0.0450], [0.6204, 1.0714, 0.0450]), .stoneDark: Self.bounds([-0.0420, 0.7500, -0.0150], [0.0420, 0.8900, 0.0150])],
                [.blackWood: Self.bounds([-0.6204, -0.0007, -0.0480], [0.6204, 1.0714, 0.0480]), .gold: Self.bounds([-0.0420, 0.7500, -0.0150], [0.0420, 0.8900, 0.0150])],
            ],
            // The kasagi's end segments are sheared, not rotated, so their ends stay vertical: x reaches 1.394 where
            // Swift's tilted beam corners reached 1.4063.
            [
                [.blackWood: Self.bounds([-1.3940, 0.0000, -0.1040], [1.3940, 2.5545, 0.1040]), .vermilion: Self.bounds([-1.1050, -0.0015, -0.0975], [1.1050, 2.2568, 0.0975])],
                [.blackWood: Self.bounds([-0.9880, 0.0000, -0.1040], [0.9880, 0.1920, 0.1040]), .stone: Self.bounds([-1.3940, -0.0015, -0.0975], [1.3940, 2.5545, 0.0975]), .stoneDark: Self.bounds([-0.0910, 1.8000, -0.0325], [0.0910, 2.1360, 0.0325])],
                [.blackWood: Self.bounds([-1.3940, -0.0015, -0.1040], [1.3940, 2.5545, 0.1040]), .gold: Self.bounds([-0.0910, 1.8000, -0.0325], [0.0910, 2.1360, 0.0325])],
            ],
        ]
        for (size, styles) in zip(sizes, expected) {
            for (style, bounds) in styles.enumerated() {
                let parameters = PropMesher.toriiParameters(width: size.width, height: size.height, thickness: size.thickness, paints: PropMesher.toriiPaints(style: style))
                try Self.expect("torii", parameters: parameters, matches: bounds)
            }
        }
    }

    @Test(arguments: [Paint.foxWhite, .foxStone, .bronze]) func foxStatue(paint: Paint) throws {
        try Self.expect("fox-statue", parameters: ["STATUE": ModelLibrary.hex(paint)], matches: [
            .bib: Self.bounds([0.0260, 0.5490, -0.0766], [0.0940, 0.6510, 0.0766]),
            paint: Self.bounds([-0.2129, 0.3554, -0.1021], [0.2000, 0.8500, 0.1021]),
            .stone: Self.bounds([-0.1500, 0.0000, -0.1500], [0.1500, 0.3000, 0.1500]),
            .stoneLight: Self.bounds([-0.1700, 0.2950, -0.1700], [0.1700, 0.3250, 0.1700]),
        ])
    }

    @Test func stoneLantern() throws {
        let kasuga = Self.bounds([-0.2078, 0.0000, -0.2400], [0.2078, 1.0010, 0.2400])
        let kasugaFire = Self.bounds([-0.1000, 0.6200, -0.1000], [0.1000, 0.7200, 0.1000])
        try Self.expect("stone-lantern", parameters: ["STYLE": .number(0), "STONE": ModelLibrary.hex(.stone)], matches: [.stone: kasuga, .lanternFire: kasugaFire])
        try Self.expect("stone-lantern", parameters: ["STYLE": .number(1), "STONE": ModelLibrary.hex(.stone)], matches: [
            .lanternFire: Self.bounds([-0.0800, 0.3500, -0.0800], [0.0800, 0.4900, 0.0800]),
            .stone: Self.bounds([-0.3291, -0.0093, -0.3800], [0.3291, 0.7225, 0.3800]),
        ])
        try Self.expect("stone-lantern", parameters: ["STYLE": .number(2), "STONE": ModelLibrary.hex(.bronze)], matches: [.bronze: kasuga, .lanternFire: kasugaFire])
        // A cell with several lanterns places each at its own spot.
        let builder = MeshBuilder()
        PropMesher.stoneLantern(builder, at: [0.5, 0, -0.25], style: 0)
        let moved = try #require(Self.paintBounds(builder)[.stone])
        #expect(simd_distance(moved.min, kasuga.min + [0.5, 0, -0.25]) < 0.01)
    }

    @Test(arguments: 0..<8) func villager(look: Int) throws {
        let expected: [[Paint: Bounds]] = [
            [
                .blackWood: Self.bounds([-0.0492, 0.1420, -0.0492], [0.0515, 0.2865, 0.0492]),
                .foxWhite: Self.bounds([-0.0500, 0.1850, -0.0500], [0.0500, 0.2521, 0.0500]),
                .gold: Self.bounds([-0.0418, 0.0220, -0.0440], [0.0418, 0.0380, 0.0440]),
                .norenRed: Self.bounds([-0.0399, 0.0000, -0.0420], [0.0399, 0.1900, 0.0420]),
            ],
            [
                .blackWood: Self.bounds([-0.0472, 0.2252, -0.0472], [0.0496, 0.2726, 0.0472]),
                .foxWhite: Self.bounds([-0.0480, 0.1752, -0.0480], [0.0480, 0.2397, 0.0480]),
                .noren: Self.bounds([-0.0552, 0.0000, -0.0580], [0.0552, 0.1800, 0.0580]),
                .sakura: Self.bounds([-0.0497, 0.0420, -0.0522], [0.0497, 0.1180, 0.0522]),
            ],
            [
                .blackWood: Self.bounds([0.0454, 0.2388, -0.0226], [0.0534, 0.2428, 0.0226]),
                .darkWood: Self.bounds([-0.0512, 0.2526, -0.0512], [0.0512, 0.2904, 0.0512]),
                .foxWhite: Self.bounds([-0.0520, 0.1848, -0.0520], [0.0520, 0.2546, 0.0520]),
                .plasterCream: Self.bounds([-0.0457, 0.0000, -0.0480], [0.0457, 0.1900, 0.0480]),
                .vermilion: Self.bounds([-0.0323, 0.0820, -0.0340], [0.0323, 0.0980, 0.0340]),
            ],
            [
                .blackWood: Self.bounds([-0.0492, 0.0520, -0.0492], [0.0515, 0.2765, 0.0492]),
                .foxWhite: Self.bounds([-0.0500, 0.1750, -0.0500], [0.0500, 0.2421, 0.0500]),
                .lanternWhite: Self.bounds([-0.0452, 0.1320, -0.0476], [0.0452, 0.1480, 0.0476]),
                .momijiOrange: Self.bounds([-0.0476, 0.0000, -0.0500], [0.0476, 0.1800, 0.0500]),
            ],
            [
                .blackWood: Self.bounds([0.0397, 0.2234, -0.0207], [0.0477, 0.2274, 0.0207]),
                .darkWood: Self.bounds([-0.0453, 0.2354, -0.0453], [0.0453, 0.2688, 0.0453]),
                .foxWhite: Self.bounds([-0.0460, 0.1754, -0.0460], [0.0460, 0.2372, 0.0460]),
                .lanternWhite: Self.bounds([-0.0542, 0.0620, -0.0570], [0.0542, 0.0780, 0.0570]),
                .sakuraDeep: Self.bounds([-0.0523, 0.0000, -0.0550], [0.0523, 0.1800, 0.0550]),
            ],
            [
                .blackWood: Self.bounds([-0.0433, 0.2416, -0.0433], [0.0458, 0.2849, 0.0433]),
                .foxWhite: Self.bounds([-0.0440, 0.1956, -0.0440], [0.0440, 0.2547, 0.0440]),
                .gold: Self.bounds([-0.0350, 0.0320, -0.0368], [0.0350, 0.1680, 0.0368]),
                .pineMid: Self.bounds([-0.0342, 0.0000, -0.0360], [0.0342, 0.2000, 0.0360]),
            ],
            [
                .blackWood: Self.bounds([-0.0492, 0.2270, -0.0492], [0.0515, 0.2765, 0.0492]),
                .foxWhite: Self.bounds([-0.0500, 0.1750, -0.0500], [0.0500, 0.2421, 0.0500]),
                .lanternWhite: Self.bounds([-0.0571, 0.0000, -0.0600], [0.0571, 0.1800, 0.0600]),
                .norenRed: Self.bounds([-0.0533, 0.0220, -0.0560], [0.0533, 0.1280, 0.0560]),
            ],
            [
                .blackWood: Self.bounds([0.0511, 0.2142, -0.0246], [0.0591, 0.2182, 0.0246]),
                .darkWood: Self.bounds([-0.0571, 0.2299, -0.0571], [0.0571, 0.2719, 0.0571]),
                .foxWhite: Self.bounds([-0.0580, 0.1542, -0.0580], [0.0580, 0.2321, 0.0580]),
                .iris: Self.bounds([-0.0476, 0.0000, -0.0500], [0.0476, 0.1600, 0.0500]),
                .umePink: Self.bounds([-0.0471, 0.0720, -0.0495], [0.0471, 0.0880, 0.0495]),
            ],
        ]
        try Self.expect("kokeshi", parameters: Villagers.parameters(look: look), matches: expected[look])
    }

    @Test func tanukiStatue() throws {
        try Self.expect("tanuki-statue", parameters: [:], matches: [
            .blackWood: Self.bounds([-0.0402, 0.4698, 0.0648], [0.0402, 0.4902, 0.0852]),
            .lattice: Self.bounds([0.1300, 0.1750, 0.1025], [0.1700, 0.2250, 0.1075]),
            .plaster: Self.bounds([0.1117, 0.1490, 0.0217], [0.1883, 0.2900, 0.0983]),
            // The union drops the back of the belly, hidden inside the body (Swift's went back to z 0.0019).
            .plasterCream: Self.bounds([-0.0936, 0.1379, 0.0479], [0.0936, 0.4798, 0.1381]),
            // The union drops the top of the head, hidden under the hat (Swift's went up to 0.5381).
            .shingle: Self.bounds([-0.1640, 0.1254, -0.1106], [0.1640, 0.5300, 0.1106]),
            .stone: Self.bounds([-0.1600, 0.0000, -0.1600], [0.1600, 0.1000, 0.1600]),
            .thatch: Self.bounds([-0.1236, 0.5300, -0.1300], [0.1236, 0.6200, 0.1300]),
        ])
    }

    @Test func tanuki() throws {
        try Self.expect("tanuki", parameters: [:], matches: [
            .bark: Self.bounds([-0.0425, 0.0000, -0.1895], [0.0425, 0.1840, 0.1583]),
            .blackWood: Self.bounds([-0.0411, -0.0008, -0.2013], [0.0411, 0.1961, 0.2068]),
            // The union drops the belly's upper half, hidden inside the body (Swift's went up to 0.1298).
            .cedar: Self.bounds([-0.0298, 0.0702, -0.0515], [0.0298, 0.1038, 0.0915]),
            .lightWood: Self.bounds([-0.0180, 0.1280, 0.1483], [0.0146, 0.1620, 0.2000]),
        ])
    }

    @Test func koi() throws {
        let body = Self.bounds([-0.0300, -0.0300, -0.1400], [0.0300, 0.0300, 0.0766])
        // The union drops the spots' lower halves, hidden inside the body (Swift's went down to -0.0031).
        let spots = Self.bounds([-0.0213, 0.0055, -0.0655], [0.0213, 0.0191, 0.0640])
        try Self.expect("koi", parameters: ["BODY": ModelLibrary.hex(.koiWhite), "SPOTS": ModelLibrary.hex(.koiOrange)], matches: [.koiWhite: body, .koiOrange: spots])
        try Self.expect("koi", parameters: ["BODY": ModelLibrary.hex(.gold), "SPOTS": ModelLibrary.hex(.gold)], matches: [.gold: body])
        try Self.expect("koi", parameters: ["BODY": ModelLibrary.hex(.blackWood), "SPOTS": ModelLibrary.hex(.koiOrange)], matches: [.blackWood: body, .koiOrange: spots])
    }

    @Test func cat() throws {
        let eyes = Self.bounds([-0.0220, 0.1490, 0.1290], [0.0220, 0.1610, 0.1410])
        let body = Self.bounds([-0.0425, 0.0000, -0.1574], [0.0425, 0.2231, 0.1340])
        try Self.expect("cat", parameters: ["FUR": ModelLibrary.hex(.foxWhite), "EAR": ModelLibrary.hex(.momijiOrange), "EYE": ModelLibrary.hex(.bamboo), "PATCHES": .number(1)], matches: [
            .bamboo: eyes,
            .blackWood: Self.bounds([-0.0505, -0.0008, -0.0688], [0.0391, 0.1387, 0.0768]),
            .foxWhite: body,
            .momijiOrange: Self.bounds([-0.0340, 0.0987, -0.0725], [0.0498, 0.2150, 0.1070]),
        ])
        try Self.expect("cat", parameters: ["FUR": ModelLibrary.hex(.blackWood), "EAR": ModelLibrary.hex(.blackWood), "EYE": ModelLibrary.hex(.ginkgoYellow), "PATCHES": .number(0)], matches: [
            .blackWood: Self.bounds([-0.0425, -0.0008, -0.1574], [0.0425, 0.2231, 0.1340]),
            .ginkgoYellow: eyes,
        ])
        try Self.expect("cat", parameters: ["FUR": ModelLibrary.hex(.plaster), "EAR": ModelLibrary.hex(.plaster), "EYE": ModelLibrary.hex(.bamboo), "PATCHES": .number(0)], matches: [
            .bamboo: eyes,
            .blackWood: Self.bounds([-0.0391, -0.0008, -0.0688], [0.0391, 0.0128, 0.0768]),
            .plaster: body,
        ])
    }

    @Test func frog() throws {
        for skin: Paint in [.momijiGreen, .cedar] {
            try Self.expect("frog", parameters: ["SKIN": ModelLibrary.hex(skin)], matches: [
                .blackWood: Self.bounds([-0.0300, 0.0620, 0.0340], [0.0300, 0.0740, 0.0460]),
                .foxWhite: Self.bounds([-0.0339, 0.0531, 0.0181], [0.0339, 0.0769, 0.0419]),
                skin: Self.bounds([-0.0620, 0.0022, -0.0548], [0.0620, 0.0605, 0.0425]),
            ])
        }
    }

    @Test func crane() throws {
        try Self.expect("crane", parameters: ["STYLE": .number(0), "BODY": ModelLibrary.hex(.foxWhite)], matches: [
            .bamboo: Self.bounds([-0.0080, 0.5500, 0.1539], [0.0080, 0.5679, 0.2300]),
            // ModelScript unions the body, dropping the crown's lower half that was hidden inside the head (0.5689).
            .bib: Self.bounds([-0.0111, 0.5770, 0.1289], [0.0111, 0.5911, 0.1511]),
            .blackWood: Self.bounds([-0.0510, 0.0000, -0.1795], [0.0510, 0.5533, 0.1402]),
            .foxWhite: Self.bounds([-0.0595, 0.2605, -0.1106], [0.0595, 0.5813, 0.1613]),
        ])
        try Self.expect("crane", parameters: ["STYLE": .number(1), "BODY": ModelLibrary.hex(.stoneLight)], matches: [
            .bamboo: Self.bounds([-0.0080, 0.5500, 0.1539], [0.0080, 0.5679, 0.2300]),
            .blackWood: Self.bounds([-0.0510, 0.0000, -0.1795], [0.0510, 0.3625, 0.0060]),
            .stoneLight: Self.bounds([-0.0595, 0.2605, -0.1106], [0.0595, 0.5813, 0.1613]),
        ])
    }

    // Recorded in meters from the Swift zen garden, seed 1234, keyed by [style, level]. At level 1, ModelScript's
    // union drops the center rock's lowest corner, hidden inside its base (Swift: x -0.9638 at level 1, z -0.9327).
    static let zenGardens: [[Int]: [Paint: Bounds]] = [
        [0, 1]: [.gravelLine: Bounds(min: [-1.7411, 0.0175, -1.6997], max: [2.3897, 0.0525, 2.2774]), .stone: Bounds(min: [-1.2749, -0.2943, -1.2749], max: [1.8486, 0.4343, 1.7720]), .stoneDark: Bounds(min: [-0.9458, -0.6355, -0.8940], max: [1.5531, 1.5990, 1.5341])],
        [0, 2]: [.gravelLine: Bounds(min: [-2.2008, 0.0175, -1.6997], max: [2.3897, 0.0525, 3.1053]), .stone: Bounds(min: [-1.6228, -0.2943, -1.2749], max: [1.8486, 0.4343, 2.5601]), .stoneDark: Bounds(min: [-1.3226, -0.6355, -0.8940], max: [1.5531, 1.5990, 2.3296])],
        [0, 3]: [.gravelLine: Bounds(min: [-2.2008, 0.0175, -1.6997], max: [3.1213, 0.0525, 3.1053]), .stone: Bounds(min: [-1.6228, -0.2943, -1.2749], max: [2.5896, 0.4343, 2.5601]), .stoneDark: Bounds(min: [-1.3226, -0.6355, -0.8940], max: [2.3510, 1.5990, 2.3296])],
        [0, 4]: [.gravelLine: Bounds(min: [-2.2008, 0.0175, -1.6997], max: [3.1213, 0.0525, 3.1053]), .stone: Bounds(min: [-1.6228, -0.2943, -1.2749], max: [2.5896, 0.4343, 2.5601]), .stoneDark: Bounds(min: [-1.3226, -0.6355, -0.8940], max: [2.3510, 1.5990, 2.3296])],
        [2, 1]: [.gravelLine: Bounds(min: [-1.7411, 0.0175, -1.6997], max: [2.3897, 0.0525, 2.2774]), .moss: Bounds(min: [-1.2749, -0.2943, -1.2749], max: [1.8486, 0.4343, 1.7720]), .stoneDark: Bounds(min: [-0.9458, -0.6355, -0.8940], max: [1.5531, 1.5990, 1.5341])],
        [2, 4]: [.gravelLine: Bounds(min: [-2.2008, 0.0175, -1.6997], max: [3.1213, 0.0525, 3.1053]), .moss: Bounds(min: [-1.6228, -0.2943, -1.2749], max: [2.5896, 0.4343, 2.5601]), .stoneDark: Bounds(min: [-1.3226, -0.6355, -0.8940], max: [2.3510, 1.5990, 2.3296])],
    ]

    // Recorded in meters from the Swift koi pond in `hexagon`, keyed by [style, seed]. In [1, 77] one koi is inside
    // the dark rock, so ModelScript's union drops it (Swift: koiOrange max x 0.8665).
    static let koiPonds: [[Int]: [Paint: Bounds]] = [
        [0, 1234]: [.koiOrange: Bounds(min: [-0.9112, -0.8418, -0.9106], max: [1.4509, -0.6632, 1.6507]), .koiWhite: Bounds(min: [-0.7643, -0.8418, 0.9728], max: [-0.0391, -0.6632, 1.3903]), .lily: Bounds(min: [-1.2030, -0.7000, -2.1224], max: [1.2340, -0.7000, 1.5479]), .lotus: Bounds(min: [-0.3197, -0.6791, 1.0237], max: [-0.0219, -0.4409, 1.3214]), .stone: Bounds(min: [-1.7242, -0.3002, -2.1426], max: [3.1837, 0.4402, 2.2753])],
        [0, 77]: [.koiOrange: Bounds(min: [-1.1306, -0.8418, -1.3368], max: [0.8665, -0.6632, 0.5329]), .lily: Bounds(min: [-2.1583, -0.7000, -2.2236], max: [0.3738, -0.7000, 1.1597]), .lotus: Bounds(min: [-1.5578, -0.6791, 0.5551], max: [-1.0497, -0.4409, 0.9332]), .stone: Bounds(min: [-3.4746, -0.2896, -2.8019], max: [2.0714, 0.4296, 1.9402])],
        [1, 1234]: [.koiOrange: Bounds(min: [-0.9112, -0.8418, -0.9106], max: [1.4509, -0.6632, 1.6507]), .koiWhite: Bounds(min: [-0.7643, -0.8418, 0.9728], max: [-0.0391, -0.6632, 1.3903]), .stone: Bounds(min: [-1.7242, -0.3002, -2.1426], max: [3.1837, 0.4402, 2.2753]), .stoneDark: Bounds(min: [-0.3943, -1.2432, -0.5955], max: [1.0943, 0.5432, 0.5955])],
        [1, 77]: [.koiOrange: Bounds(min: [-1.1306, -0.8418, -1.3368], max: [0.2712, -0.6632, 0.5329]), .stone: Bounds(min: [-3.4746, -0.2896, -2.8019], max: [2.0714, 0.4296, 1.9402]), .stoneDark: Bounds(min: [-0.3943, -1.2432, -0.5955], max: [1.0943, 0.5432, 0.5955])],
        [2, 1234]: [.iris: Bounds(min: [-1.3320, 0.6509, -2.5941], max: [2.5694, 0.8891, 1.7802]), .koiOrange: Bounds(min: [-0.9112, -0.8418, -0.9106], max: [1.4509, -0.6632, 1.6507]), .koiWhite: Bounds(min: [-0.7643, -0.8418, 0.9728], max: [-0.0391, -0.6632, 1.3903]), .lily: Bounds(min: [-1.3243, -0.7173, -2.6856], max: [2.6177, 0.8750, 1.7440]), .stone: Bounds(min: [-1.7242, -0.3002, -2.1426], max: [3.1837, 0.4402, 2.2753])],
        [2, 77]: [.iris: Bounds(min: [-2.6852, 0.6509, -2.7374], max: [0.1032, 0.8891, 1.2302]), .koiOrange: Bounds(min: [-1.1306, -0.8418, -1.3368], max: [0.8665, -0.6632, 0.5329]), .lily: Bounds(min: [-2.7808, -0.7177, -2.8928], max: [0.1480, 0.8750, 1.1781]), .stone: Bounds(min: [-3.4746, -0.2896, -2.8019], max: [2.0714, 0.4296, 1.9402])],
    ]

    @Test(arguments: Array(koiPonds.keys)) func koiPond(key: [Int]) {
        let item = Item(kind: .koiPond, style: key[0], level: 1, group: 0, seed: UInt32(key[1]), rotation: 0)
        Self.expectProp(item, polygon: Self.hexagon, matches: Self.koiPonds[key]!)
    }

    @Test(arguments: Array(zenGardens.keys)) func zenGarden(key: [Int]) {
        let item = Item(kind: .zenGarden, style: key[0], level: key[1], group: 0, seed: 1234, rotation: 0)
        Self.expectProp(item, matches: Self.zenGardens[key]!)
    }
}
