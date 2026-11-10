import Metal
import SceneSprockets
import simd
import SwiftMesh

// Collects flat-shaded triangles, one submesh per palette color.
final class MeshBuilder {
    private(set) var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var coordinates: [SIMD2<Float>] = []
    // One submesh per surface; the paint is a palette texture coordinate, so a whole chunk is one or two draws.
    private var groups: [Surface: [UInt32]] = [:]
    private var order: [Surface] = []
    // Applied to every point added, for building things in local space.
    var transform: simd_float4x4 = matrix_identity_float4x4
    private var isIdentity = true

    func setTransform(_ matrix: simd_float4x4) {
        transform = matrix
        isIdentity = matrix == matrix_identity_float4x4
    }

    func resetTransform() {
        setTransform(matrix_identity_float4x4)
    }

    private func apply(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard !isIdentity else {
            return point
        }
        let result = transform * SIMD4<Float>(point, 1)
        return [result.x, result.y, result.z]
    }

    var maxY: Float {
        positions.map(\.y).max() ?? 0
    }

    // Normal points away from `center` (given in the same space as the points).
    func triangle(_ paint: Paint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, outwardFrom center: SIMD3<Float>) {
        let a = apply(a), b = apply(b), c = apply(c), center = apply(center)
        var normal = simd_cross(b - a, c - a)
        guard simd_length_squared(normal) > 1e-14 else {
            return
        }
        normal = simd_normalize(normal)
        if simd_dot(normal, (a + b + c) / 3 - center) < 0 {
            normal = -normal
        }
        add(paint, a, b, c, normal: normal)
    }

    // Counterclockwise winding faces the normal.
    func triangle(_ paint: Paint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let a = apply(a), b = apply(b), c = apply(c)
        let normal = simd_cross(b - a, c - a)
        guard simd_length_squared(normal) > 1e-14 else {
            return
        }
        add(paint, a, b, c, normal: simd_normalize(normal))
    }

    private func add(_ paint: Paint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>) {
        let surface = paint.surface
        if groups[surface] == nil {
            groups[surface] = []
            order.append(surface)
        }
        let start = UInt32(positions.count)
        positions += [a, b, c]
        normals += [normal, normal, normal]
        let coordinate = paint.paletteCoordinate
        coordinates += [coordinate, coordinate, coordinate]
        groups[surface]! += [start, start + 1, start + 2]
    }

    func quad(_ paint: Paint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, outwardFrom center: SIMD3<Float>) {
        triangle(paint, a, b, c, outwardFrom: center)
        triangle(paint, a, c, d, outwardFrom: center)
    }

    // A quad facing `normal`.
    func panel(_ paint: Paint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, facing normal: SIMD3<Float>) {
        let center = (a + b + c + d) / 4 - normal
        quad(paint, a, b, c, d, outwardFrom: center)
    }

    // A flat polygon (convex-ish) at its own heights, facing up or down.
    func cap(_ paint: Paint, _ points: [SIMD3<Float>], up: Bool = true) {
        guard points.count >= 3 else {
            return
        }
        let center = points.reduce(.zero, +) / Float(points.count)
        let reference = center + SIMD3<Float>(0, up ? -10 : 10, 0)
        for index in points.indices {
            triangle(paint, center, points[index], points[(index + 1) % points.count], outwardFrom: reference)
        }
    }

    func box(_ paint: Paint, center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float = 0) {
        let half = size / 2
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        func corner(_ sx: Float, _ sy: Float, _ sz: Float) -> SIMD3<Float> {
            center + rotation.act([sx * half.x, sy * half.y, sz * half.z])
        }
        let c = [corner(-1, -1, -1), corner(1, -1, -1), corner(1, 1, -1), corner(-1, 1, -1),
                 corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)]
        let faces = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (3, 2, 6, 7), (0, 3, 7, 4), (1, 2, 6, 5)]
        for face in faces {
            quad(paint, c[face.0], c[face.1], c[face.2], c[face.3], outwardFrom: center)
        }
    }

    // A box stretched between two points, with a cross section of width (horizontal) by height.
    func beam(_ paint: Paint, from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float, height: Float) {
        let axis = b - a
        let length = simd_length(axis)
        guard length > 1e-5 else {
            return
        }
        let forward = axis / length
        let reference: SIMD3<Float> = abs(forward.y) < 0.95 ? [0, 1, 0] : [1, 0, 0]
        let side = simd_normalize(simd_cross(forward, reference))
        let up = simd_cross(side, forward)
        let center = (a + b) / 2
        let w = side * (width / 2)
        let h = up * (height / 2)
        let corners = [a - w - h, a + w - h, a + w + h, a - w + h, b - w - h, b + w - h, b + w + h, b - w + h]
        let faces = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (3, 2, 6, 7), (0, 3, 7, 4), (1, 2, 6, 5)]
        for face in faces {
            quad(paint, corners[face.0], corners[face.1], corners[face.2], corners[face.3], outwardFrom: center)
        }
    }

    func frustum(_ paint: Paint, from a: SIMD3<Float>, to b: SIMD3<Float>, radiusA: Float, radiusB: Float, sides: Int = 7, caps: Bool = false) {
        let axis = simd_normalize(b - a)
        let reference: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, reference))
        let v = simd_cross(axis, u)
        func ring(_ center: SIMD3<Float>, _ radius: Float) -> [SIMD3<Float>] {
            (0..<sides).map { index in
                let angle = Float(index) / Float(sides) * 2 * .pi
                return center + (u * cos(angle) + v * sin(angle)) * radius
            }
        }
        let lower = ring(a, radiusA)
        let upper = ring(b, radiusB)
        let middle = (a + b) / 2
        for index in 0..<sides {
            let next = (index + 1) % sides
            triangle(paint, lower[index], lower[next], upper[next], outwardFrom: middle)
            triangle(paint, lower[index], upper[next], upper[index], outwardFrom: middle)
        }
        if caps {
            for index in 0..<sides {
                let next = (index + 1) % sides
                triangle(paint, a, lower[index], lower[next], outwardFrom: middle)
                triangle(paint, b, upper[index], upper[next], outwardFrom: middle)
            }
        }
    }

    func cylinder(_ paint: Paint, from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, sides: Int = 8) {
        frustum(paint, from: a, to: b, radiusA: radius, radiusB: radius, sides: sides, caps: true)
    }

    func cone(_ paint: Paint, base: SIMD3<Float>, tip: SIMD3<Float>, radius: Float, sides: Int = 6, capped: Bool = false) {
        let axis = simd_normalize(tip - base)
        let reference: SIMD3<Float> = abs(axis.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(axis, reference))
        let v = simd_cross(axis, u)
        let ring = (0..<sides).map { index -> SIMD3<Float> in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return base + (u * cos(angle) + v * sin(angle)) * radius
        }
        let center = base + (tip - base) * 0.3
        for index in 0..<sides {
            triangle(paint, ring[index], ring[(index + 1) % sides], tip, outwardFrom: center)
            if capped {
                triangle(paint, ring[index], ring[(index + 1) % sides], base, outwardFrom: center)
            }
        }
    }

    func blob(_ paint: Paint, center: SIMD3<Float>, scale: SIMD3<Float>, rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        let points = Self.icosahedronVertices.map { center + rotation.act($0 * scale) }
        for face in Self.icosahedronFaces {
            triangle(paint, points[face.0], points[face.1], points[face.2], outwardFrom: center)
        }
    }

    // A flat disc lying on the ground.
    func disc(_ paint: Paint, center: SIMD3<Float>, radius: Float, sides: Int = 10) {
        let points = (0..<sides).map { index -> SIMD3<Float> in
            let angle = Float(index) / Float(sides) * 2 * .pi
            return center + [cos(angle) * radius, 0, sin(angle) * radius]
        }
        cap(paint, points)
    }

    var isEmpty: Bool {
        positions.isEmpty
    }

    // Adds another builder's triangles as they are (its transform was already applied).
    func append(_ other: MeshBuilder) {
        let start = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        coordinates += other.coordinates
        for surface in other.order {
            if groups[surface] == nil {
                groups[surface] = []
                order.append(surface)
            }
            groups[surface]! += other.groups[surface]!.map { $0 + start }
        }
    }

    struct Built {
        var mesh: MetalMesh
        var surfaces: [Surface]
        var maxY: Float
    }

    func build(device: MTLDevice, label: String) -> Built? {
        guard !positions.isEmpty else {
            return nil
        }
        let mesh = MetalMesh(
            device: device,
            attributes: [.positions(positions), .normals(normals), .textureCoordinates(coordinates)],
            submeshes: order.map { MetalMesh.SubmeshIndices(label: "\($0)", indices: groups[$0]!) },
            label: label
        )
        return Built(mesh: mesh, surfaces: order, maxY: maxY)
    }

    private static let icosahedronVertices: [SIMD3<Float>] = {
        let t = (1 + sqrt(Float(5))) / 2
        let raw: [SIMD3<Float>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]
        ]
        return raw.map(simd_normalize)
    }()

    private static let icosahedronFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)
    ]
}
