import Foundation
import ModelScript
import simd

// ModelScript files in the bundle's Models folder. Their colors must be Paint colors: compiled models keep only
// colors, so each triangle is matched back to the nearest Paint.
enum ModelLibrary {
    enum Failure: Error {
        case missing(String)
    }

    static func compile(_ name: String, parameters: [String: ModelParameter] = [:]) throws -> CompiledModel {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Models") else {
            throw Failure.missing(name)
        }
        return try ModelDocument(contentsOf: url, parameters: parameters).compile()
    }

    static func hex(_ paint: Paint) -> ModelParameter {
        .color(String(format: "#%06X", paint.hex))
    }
}

extension Paint {
    // Highlights are for the editor and share colors with nothing a model should use.
    private static let modelPaints = allCases.filter { $0 != .highlight && $0 != .highlightStretch }

    static func nearest(to linear: SIMD3<Float>) -> Paint {
        modelPaints.min { simd_distance_squared($0.color, linear) < simd_distance_squared($1.color, linear) }!
    }
}

extension MeshBuilder {
    func append(_ model: CompiledModel) {
        for triangle in model.body.coloredTriangles() {
            let (a, b, c) = triangle.positions
            self.triangle(Paint.nearest(to: triangle.color), a, b, c)
        }
    }
}
