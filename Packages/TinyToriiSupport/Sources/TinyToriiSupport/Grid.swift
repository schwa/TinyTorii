import simd

// An organic grid: Lloyd-relaxed Voronoi cells on an island with a ragged coast. Positions are (x, z) in world units.
public struct Grid: Sendable {
    public struct Cell: Sendable {
        // Counterclockwise indices into `vertices`, seen from above (+y).
        public var polygon: [Int]
        // The cell across edge i (polygon[i] -> polygon[i + 1]); nil on the coast.
        public var neighbors: [Int?]
        public var site: SIMD2<Float>
        public var center: SIMD2<Float>
        public var area: Float
    }

    public var vertices: [SIMD2<Float>]
    public var cells: [Cell]
    public var radius: Float
    public var spacing: Float
    // Cells around each vertex.
    public var vertexCells: [[Int]]
    private var buckets: [SIMD2<Int32>: [Int]]

    public func polygon(of cell: Int) -> [SIMD2<Float>] {
        cells[cell].polygon.map { vertices[$0] }
    }

    public func neighborSet(of cell: Int) -> [Int] {
        cells[cell].neighbors.compactMap(\.self)
    }

    // The cell whose site is nearest, which is the Voronoi cell holding the point.
    public func cell(at point: SIMD2<Float>) -> Int? {
        let key = SIMD2<Int32>(Int32((point.x / spacing).rounded(.down)), Int32((point.y / spacing).rounded(.down)))
        var best: Int?
        var bestDistance = Float.infinity
        for dx in -2...2 {
            for dy in -2...2 {
                for index in buckets[key &+ SIMD2(Int32(dx), Int32(dy))] ?? [] {
                    let distance = simd_distance_squared(cells[index].site, point)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = index
                    }
                }
            }
        }
        guard let best, contains(cell: best, point: point) else {
            return nil
        }
        return best
    }

    public func contains(cell: Int, point: SIMD2<Float>) -> Bool {
        let points = polygon(of: cell)
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            let edge = b - a
            let toPoint = point - a
            if edge.x * toPoint.y - edge.y * toPoint.x < -1e-4 {
                return false
            }
        }
        return true
    }

    // Sizes in meters.
    public init(radius: Float = 91, spacing: Float = 7.35, seed: UInt32 = 1, relaxations: Int = 2) {
        self.radius = radius
        self.spacing = spacing
        var random = SeededRandom(seed: seed &* 2_654_435_761 &+ 17)

        // Coastline: a wobbly circle.
        let phases = (0..<4).map { _ in random.range(0, 2 * .pi) }
        func coast(_ angle: Float) -> Float {
            radius * (1 + 0.07 * sin(3 * angle + phases[0]) + 0.05 * sin(5 * angle + phases[1]) + 0.03 * sin(9 * angle + phases[2]))
        }

        // Blue-noise sites by dart throwing; outside the coast, fixed ghost sites bound the coastal cells.
        var sites: [SIMD2<Float>] = []
        var ghosts: [SIMD2<Float>] = []
        let minimumDistance = spacing * 0.78
        var dartBuckets: [SIMD2<Int32>: [SIMD2<Float>]] = [:]
        func dartKey(_ point: SIMD2<Float>) -> SIMD2<Int32> {
            SIMD2(Int32((point.x / minimumDistance).rounded(.down)), Int32((point.y / minimumDistance).rounded(.down)))
        }
        let extent = radius * 1.25 + spacing * 3
        var misses = 0
        while misses < 4_000 {
            let point = SIMD2<Float>(random.signed(), random.signed()) * extent
            let key = dartKey(point)
            var isFar = true
            search: for dx in -1...1 {
                for dy in -1...1 {
                    for other in dartBuckets[key &+ SIMD2(Int32(dx), Int32(dy))] ?? [] where simd_distance(other, point) < minimumDistance {
                        isFar = false
                        break search
                    }
                }
            }
            guard isFar else {
                misses += 1
                continue
            }
            misses = 0
            dartBuckets[key, default: []].append(point)
            let edge = coast(atan2(point.y, point.x))
            let distance = simd_length(point)
            if distance < edge {
                sites.append(point)
            } else if distance < edge + spacing * 2.5 {
                ghosts.append(point)
            }
        }

        var polygons: [[SIMD2<Float>]] = []
        for iteration in 0...relaxations {
            polygons = Self.voronoi(sites: sites, ghosts: ghosts, spacing: spacing)
            if iteration < relaxations {
                for index in sites.indices where polygons[index].count >= 3 {
                    sites[index] = Self.centroid(polygons[index])
                }
            }
        }

        // Weld the corners that cells share, so the grid has real topology.
        var vertices: [SIMD2<Float>] = []
        var weld: [SIMD2<Int32>: [Int]] = [:]
        let tolerance: Float = spacing * 0.03
        func vertexIndex(_ point: SIMD2<Float>) -> Int {
            let key = SIMD2<Int32>(Int32((point.x / tolerance).rounded(.down)), Int32((point.y / tolerance).rounded(.down)))
            for dx in -1...1 {
                for dy in -1...1 {
                    for index in weld[key &+ SIMD2(Int32(dx), Int32(dy))] ?? [] where simd_distance(vertices[index], point) < tolerance {
                        return index
                    }
                }
            }
            vertices.append(point)
            weld[key, default: []].append(vertices.count - 1)
            return vertices.count - 1
        }

        var cells: [Cell] = []
        for (index, points) in polygons.enumerated() {
            var polygon: [Int] = []
            for point in points {
                let vertex = vertexIndex(point)
                if polygon.last != vertex {
                    polygon.append(vertex)
                }
            }
            if polygon.count > 1, polygon.first == polygon.last {
                polygon.removeLast()
            }
            guard polygon.count >= 3 else {
                continue
            }
            let welded = polygon.map { vertices[$0] }
            cells.append(Cell(polygon: polygon, neighbors: [], site: sites[index], center: Self.centroid(welded), area: Self.area(welded)))
        }

        var edgeOwner: [SIMD2<Int32>: Int] = [:]
        for (cellIndex, cell) in cells.enumerated() {
            for index in cell.polygon.indices {
                let a = cell.polygon[index]
                let b = cell.polygon[(index + 1) % cell.polygon.count]
                edgeOwner[SIMD2(Int32(a), Int32(b))] = cellIndex
            }
        }
        var vertexCells = [[Int]](repeating: [], count: vertices.count)
        for cellIndex in cells.indices {
            var neighbors: [Int?] = []
            let polygon = cells[cellIndex].polygon
            for index in polygon.indices {
                let a = polygon[index]
                let b = polygon[(index + 1) % polygon.count]
                neighbors.append(edgeOwner[SIMD2(Int32(b), Int32(a))])
                vertexCells[a].append(cellIndex)
            }
            cells[cellIndex].neighbors = neighbors
        }

        var buckets: [SIMD2<Int32>: [Int]] = [:]
        for (index, cell) in cells.enumerated() {
            let key = SIMD2<Int32>(Int32((cell.site.x / spacing).rounded(.down)), Int32((cell.site.y / spacing).rounded(.down)))
            buckets[key, default: []].append(index)
        }
        self.vertices = vertices
        self.cells = cells
        self.vertexCells = vertexCells
        self.buckets = buckets
    }

    private static func voronoi(sites: [SIMD2<Float>], ghosts: [SIMD2<Float>], spacing: Float) -> [[SIMD2<Float>]] {
        let all = sites + ghosts
        var buckets: [SIMD2<Int32>: [Int]] = [:]
        let bucketSize = spacing * 1.5
        func key(_ point: SIMD2<Float>) -> SIMD2<Int32> {
            SIMD2(Int32((point.x / bucketSize).rounded(.down)), Int32((point.y / bucketSize).rounded(.down)))
        }
        for (index, point) in all.enumerated() {
            buckets[key(point), default: []].append(index)
        }
        return sites.indices.map { index in
            let site = sites[index]
            let half = spacing * 2
            var polygon: [SIMD2<Float>] = [site + [-half, -half], site + [half, -half], site + [half, half], site + [-half, half]]
            let center = key(site)
            for dx in -2...2 {
                for dy in -2...2 {
                    for other in buckets[center &+ SIMD2(Int32(dx), Int32(dy))] ?? [] where other != index {
                        polygon = clip(polygon, keepingSideOf: site, against: all[other])
                    }
                }
            }
            return polygon
        }
    }

    // Keeps the part of a convex polygon nearer `site` than `other`.
    private static func clip(_ polygon: [SIMD2<Float>], keepingSideOf site: SIMD2<Float>, against other: SIMD2<Float>) -> [SIMD2<Float>] {
        let normal = other - site
        let middle = (site + other) / 2
        func side(_ point: SIMD2<Float>) -> Float {
            simd_dot(point - middle, normal)
        }
        var result: [SIMD2<Float>] = []
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let a = side(current)
            let b = side(next)
            if a <= 0 {
                result.append(current)
            }
            if (a < 0 && b > 0) || (a > 0 && b < 0) {
                result.append(current + (next - current) * (a / (a - b)))
            }
        }
        return result
    }

    static func area(_ polygon: [SIMD2<Float>]) -> Float {
        var sum: Float = 0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func centroid(_ polygon: [SIMD2<Float>]) -> SIMD2<Float> {
        var sum = SIMD2<Float>.zero
        var areaSum: Float = 0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let cross = a.x * b.y - b.x * a.y
            sum += (a + b) * cross
            areaSum += cross
        }
        guard abs(areaSum) > 1e-8 else {
            return polygon.reduce(.zero, +) / Float(max(polygon.count, 1))
        }
        return sum / (3 * areaSum)
    }
}
