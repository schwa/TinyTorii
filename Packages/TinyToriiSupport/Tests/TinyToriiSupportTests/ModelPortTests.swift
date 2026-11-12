import Foundation
import simd
import Testing
import ModelScript
@testable import TinyToriiSupport

// Models moved from hand-written Swift to ModelScript files must keep their shape: each paint's bounding box is
// checked against the one the Swift geometry made, recorded before the move.
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
            #expect(error < 0.008, "\(name) \(parameters) .\(paint): \(found), expected \(bounds)", sourceLocation: sourceLocation)
        }
    }

    static func bounds(_ min: SIMD3<Float>, _ max: SIMD3<Float>) -> Bounds {
        Bounds(min: min, max: max)
    }

    // Paint.nearest can only find a paint whose color no other paint shares.
    @Test func everyPaintRoundTripsThroughItsColor() {
        for paint in Paint.allCases where paint != .highlight && paint != .highlightStretch {
            #expect(Paint.nearest(to: paint.color) == paint, "\(paint)")
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
}
