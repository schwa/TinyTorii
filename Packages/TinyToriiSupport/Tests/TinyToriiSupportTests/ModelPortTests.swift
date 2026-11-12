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
