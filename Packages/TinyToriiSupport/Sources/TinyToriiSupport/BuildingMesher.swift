import simd

// A cell's outline as part of its building: which edges face outside, and how each corner moves when walls inset.
struct Footprint {
    var points: [SIMD2<Float>]
    var center: SIMD2<Float>
    var exterior: [Bool]
    // Miter direction per corner; nil for corners inside the building.
    var outward: [SIMD2<Float>?]

    init(town: Town, cell: Int) {
        let grid = town.grid
        let gridCell = grid.cells[cell]
        points = grid.polygon(of: cell)
        center = gridCell.center
        exterior = gridCell.neighbors.map { !town.joins(cell, $0) }
        func inBuilding(_ other: Int?) -> Bool {
            guard let other else {
                return false
            }
            return other == cell || town.joins(cell, other)
        }
        outward = gridCell.polygon.map { vertex in
            var normals: [SIMD2<Float>] = []
            for other in grid.vertexCells[vertex] where inBuilding(other) {
                let otherCell = grid.cells[other]
                let count = otherCell.polygon.count
                for index in 0..<count {
                    let a = otherCell.polygon[index]
                    let b = otherCell.polygon[(index + 1) % count]
                    guard a == vertex || b == vertex, !inBuilding(otherCell.neighbors[index]) else {
                        continue
                    }
                    let pa = grid.vertices[a], pb = grid.vertices[b]
                    var normal = simd_normalize((pb - pa).perpendicular)
                    if simd_dot(normal, (pa + pb) / 2 - otherCell.center) < 0 {
                        normal = -normal
                    }
                    normals.append(normal)
                }
            }
            guard !normals.isEmpty else {
                return nil
            }
            let total = normals.reduce(.zero, +)
            guard simd_length(total) > 1e-4 else {
                return normals[0]
            }
            let sum = simd_normalize(total)
            let minimum = normals.map { simd_dot(sum, $0) }.min() ?? 1
            return sum / max(minimum, 0.35)
        }
    }

    // A corner moved by `distance` along its miter (negative: inward). Inner corners do not move.
    func offset(_ index: Int, _ distance: Float) -> SIMD2<Float> {
        guard let direction = outward[index] else {
            return points[index]
        }
        return points[index] + direction * distance
    }

    func edgeNormal(_ index: Int) -> SIMD2<Float> {
        let a = points[index], b = points[(index + 1) % points.count]
        var normal = simd_normalize((b - a).perpendicular)
        if simd_dot(normal, (a + b) / 2 - center) < 0 {
            normal = -normal
        }
        return normal
    }

    var count: Int {
        points.count
    }

    func next(_ index: Int) -> Int {
        (index + 1) % points.count
    }

    var longestExteriorEdge: Int? {
        points.indices.filter { exterior[$0] }.max { simd_distance(points[$0], points[next($0)]) < simd_distance(points[$1], points[next($1)]) }
    }
}

struct BuildingSpec {
    var wall: Paint = .plaster
    var upperWall: Paint?
    var timber: Paint = .darkWood
    var roof: Paint = .tileGrey
    var ridge: Paint?
    var soffit: Paint = .darkWood
    var plinth: Paint = .stoneDark
    var plinthHeight: Float = 0.12
    var storyHeight: Float = 0.8
    var roofRise: Float = 0.6
    var overhang: Float = 0.3
    var curve: Float = 1.6
    var fascia: Float = 0.06
    var wallInset: Float = 0.16
    var tierInset: Float = 0
    var skirts = false
    var skirtOverhang: Float = 0.28
    var skirtRise: Float = 0.25
    var stoneBase: Float = 0
    var stilts: Float = 0
    var windows: Paint = .shoji
    var lattice = false
    var balcony = false
    var door: Paint? = .noren
    var lanterns = false
    var chigi = false
    var shachi = false
    var spire = false
    var pointed = false
    var columns: Paint?
    var namako = false
    var deck = false

    static func make(kind: Kind, style: Int, level: Int) -> BuildingSpec {
        var spec = BuildingSpec()
        switch kind {
        case .machiya:
            spec.storyHeight = 0.72
            spec.roofRise = 0.42
            spec.overhang = 0.24
            spec.skirts = true
            spec.lattice = true
            spec.wallInset = 0.08
            switch style {
            case 1:
                spec.wall = .plasterCream
                spec.timber = .cedar
                spec.roof = .tileBlue
                spec.door = .norenRed
            case 2:
                spec.wall = .earthWall
                spec.upperWall = .plaster
                spec.timber = .blackWood
                spec.roof = .tileGrey
                spec.lanterns = true
            default:
                spec.wall = .darkWood
                spec.upperWall = .plaster
                spec.timber = .blackWood
            }
        case .minka:
            spec.storyHeight = 0.78
            spec.roofRise = 1.25
            spec.overhang = 0.38
            spec.curve = 1.05
            spec.fascia = 0.16
            spec.wallInset = 0.22
            spec.wall = .earthWall
            spec.timber = .darkWood
            spec.roof = .thatch
            spec.ridge = .thatchDark
            spec.soffit = .thatchDark
            spec.door = nil
            switch style {
            case 1:
                spec.roof = .shingle
                spec.ridge = .darkWood
                spec.soffit = .darkWood
                spec.wall = .plasterCream
                spec.roofRise = 0.9
                spec.fascia = 0.08
            case 2:
                spec.roof = .snowRoof
                spec.ridge = .thatchDark
                spec.wall = .plaster
                spec.roofRise = 1.5
            default:
                break
            }
        case .ryokan:
            spec.storyHeight = 0.82
            spec.roofRise = 0.55
            spec.overhang = 0.34
            spec.wall = .plasterCream
            spec.timber = .darkWood
            spec.roof = .tileBlue
            spec.balcony = true
            spec.lanterns = true
            spec.door = .noren
            spec.wallInset = 0.2
            switch style {
            case 1:
                spec.wall = .plaster
                spec.timber = .blackWood
                spec.roof = .tileGrey
                spec.skirts = true
                spec.door = .norenRed
            case 2:
                spec.wall = .lightWood
                spec.timber = .cedar
                spec.roof = .shingle
                spec.deck = true
            default:
                break
            }
        case .teahouse:
            spec.storyHeight = 0.62
            spec.roofRise = 0.5
            spec.overhang = 0.3
            spec.curve = 1.2
            spec.wall = .earthWall
            spec.timber = .cedar
            spec.roof = .shingle
            spec.wallInset = 0.42
            spec.door = nil
            spec.deck = true
            switch style {
            case 1:
                spec.stilts = 0.35
                spec.wall = .plasterCream
                spec.roof = .thatch
                spec.ridge = .thatchDark
                spec.curve = 1.0
                spec.roofRise = 0.75
            case 2:
                spec.wall = .plaster
                spec.roof = .copper
                spec.timber = .blackWood
                spec.stilts = 0.15
            default:
                break
            }
        case .kura:
            spec.storyHeight = 0.9
            spec.roofRise = 0.5
            spec.overhang = 0.18
            spec.curve = 1.3
            spec.wall = .plaster
            spec.timber = .blackWood
            spec.roof = .tileGrey
            spec.windows = .blackWood
            spec.door = nil
            spec.wallInset = 0.25
            spec.plinthHeight = 0.2
            switch style {
            case 1: spec.namako = true
            case 2:
                spec.wall = .blackWood
                spec.windows = .plaster
            default: break
            }
        case .castle:
            spec.storyHeight = 0.72
            spec.roofRise = 0.55
            spec.overhang = 0.34
            spec.curve = 2.0
            spec.wall = .plaster
            spec.timber = .blackWood
            spec.roof = .tileBlue
            spec.stoneBase = 1.1
            spec.tierInset = 0.2
            spec.skirts = true
            spec.skirtOverhang = 0.36
            spec.skirtRise = 0.3
            spec.shachi = true
            spec.windows = .blackWood
            spec.door = nil
            spec.wallInset = 0.05
            switch style {
            case 1:
                spec.wall = .blackWood
                spec.timber = .darkWood
                spec.windows = .plaster
                spec.roof = .tileGrey
            case 2:
                spec.roof = .copper
            default: break
            }
        case .pagoda:
            spec.storyHeight = 0.62
            spec.roofRise = 0.4
            spec.overhang = 0.5
            spec.curve = 2.2
            spec.wall = .vermilion
            spec.timber = .vermilionDark
            spec.roof = .tileGrey
            spec.tierInset = 0.08
            spec.skirts = true
            spec.skirtOverhang = 0.55
            spec.skirtRise = 0.32
            spec.spire = true
            spec.pointed = true
            spec.windows = .lattice
            spec.door = nil
            spec.wallInset = 0.42
            spec.plinthHeight = 0.25
            switch style {
            case 1:
                spec.wall = .cedar
                spec.timber = .darkWood
                spec.roof = .shingle
            case 2:
                spec.wall = .blackWood
                spec.timber = .gold
                spec.roof = .copper
            default: break
            }
        case .shrine:
            spec.storyHeight = 0.7
            spec.roofRise = 0.75
            spec.overhang = 0.4
            spec.curve = 1.3
            spec.wall = .plaster
            spec.timber = .vermilion
            spec.columns = .vermilion
            spec.roof = .copper
            spec.stilts = 0.25
            spec.deck = true
            spec.chigi = true
            spec.door = nil
            spec.windows = .lattice
            spec.wallInset = 0.3
            switch style {
            case 1:
                spec.timber = .lightWood
                spec.columns = .lightWood
                spec.wall = .lightWood
                spec.roof = .thatch
                spec.ridge = .thatchDark
                spec.curve = 1.0
                spec.roofRise = 0.95
            case 2:
                spec.timber = .gold
                spec.columns = .blackWood
                spec.wall = .vermilion
                spec.roof = .copper
            default: break
            }
        case .temple:
            spec.storyHeight = 1.05
            spec.roofRise = 0.95
            spec.overhang = 0.5
            spec.curve = 2.0
            spec.wall = .plasterCream
            spec.timber = .darkWood
            spec.columns = .darkWood
            spec.roof = .tileGrey
            spec.door = nil
            spec.windows = .lattice
            spec.plinthHeight = 0.3
            spec.plinth = .stone
            spec.wallInset = 0.2
            spec.skirts = true
            switch style {
            case 1:
                spec.roof = .copper
                spec.columns = .vermilion
                spec.timber = .vermilion
            case 2:
                spec.wall = .gold
                spec.timber = .blackWood
                spec.columns = .blackWood
                spec.roof = .shingle
            default: break
            }
        default:
            break
        }
        return spec
    }
}

enum BuildingMesher {
    static func build(_ builder: MeshBuilder, town: Town, cell: Int, item: Item) {
        let footprint = Footprint(town: town, cell: cell)
        var spec = BuildingSpec.make(kind: item.kind, style: item.style, level: item.level)
        // Every building is a little different; stretched cells share a seed, so a building stays consistent.
        var variation = SeededRandom(seed: item.seed)
        spec.storyHeight *= variation.range(0.94, 1.08)
        spec.roofRise *= variation.range(0.88, 1.15)
        spec.overhang *= variation.range(0.9, 1.1)
        // One spire per building, on its first cell.
        if spec.spire, town.cells.indices.contains(where: { $0 < cell && town.cells[$0].item?.group == item.group }) {
            spec.spire = false
        }
        var y = town.standingHeight(cell)
        let tiers: Int = item.level
        let inset = spec.wallInset

        // Base: a battered stone wall, stilts, or a stone plinth.
        if spec.stoneBase > 0 {
            let height = spec.stoneBase
            for index in 0..<footprint.count where footprint.exterior[index] {
                let next = footprint.next(index)
                let a0 = footprint.offset(index, -inset + 0.3).lifted(y)
                let b0 = footprint.offset(next, -inset + 0.3).lifted(y)
                let a1 = footprint.offset(index, -inset).lifted(y + height)
                let b1 = footprint.offset(next, -inset).lifted(y + height)
                builder.quad(.stone, a0, b0, b1, a1, outwardFrom: footprint.center.lifted(y + height / 2))
                // Mortar courses.
                for course in 1..<4 {
                    let t = Float(course) / 4
                    let ca = mix3(a0, a1, t) + footprint.edgeNormal(index).lifted(0) * 0.012
                    let cb = mix3(b0, b1, t) + footprint.edgeNormal(index).lifted(0) * 0.012
                    builder.beam(.stoneDark, from: ca, to: cb, width: 0.02, height: 0.03)
                }
            }
            builder.cap(.stoneLight, footprint.points.indices.map { footprint.offset($0, -inset).lifted(y + height) })
            y += height
        } else {
            let height = spec.plinthHeight
            prism(builder, spec.plinth, footprint: footprint, offset: -inset + 0.06, from: y - 0.1, to: y + height)
            y += height
        }
        if spec.stilts > 0 {
            for index in 0..<footprint.count where footprint.outward[index] != nil {
                let point = footprint.offset(index, -inset)
                builder.box(spec.timber, center: point.lifted(y + spec.stilts / 2), size: [0.08, spec.stilts, 0.08])
            }
            y += spec.stilts
        }
        if spec.deck || spec.stilts > 0 {
            let deck = footprint.points.indices.map { footprint.offset($0, -inset + 0.18).lifted(y) }
            builder.cap(.lightWood, deck)
            for index in 0..<footprint.count where footprint.exterior[index] {
                let next = footprint.next(index)
                let a = footprint.offset(index, -inset + 0.18), b = footprint.offset(next, -inset + 0.18)
                builder.quad(.cedar, a.lifted(y), b.lifted(y), b.lifted(y - 0.06), a.lifted(y - 0.06), outwardFrom: footprint.center.lifted(y))
            }
        }

        let doorEdge = footprint.longestExteriorEdge
        var random = SeededRandom(seed: item.seed)
        for tier in 0..<tiers {
            let offset = -inset - Float(tier) * spec.tierInset
            let y0 = y + Float(tier) * spec.storyHeight
            let y1 = y0 + spec.storyHeight
            let wallPaint = tier > 0 ? (spec.upperWall ?? spec.wall) : spec.wall
            walls(builder, wallPaint, footprint: footprint, offset: offset, from: y0, to: y1)
            if spec.namako {
                walls(builder, .stoneDark, footprint: footprint, offset: offset + 0.015, from: y0, to: y0 + spec.storyHeight * 0.35)
            }
            // Beams at the bottom and top of each story, and posts at the corners.
            bands(builder, spec.timber, footprint: footprint, offset: offset + 0.02, from: y1 - 0.07, to: y1)
            bands(builder, spec.timber, footprint: footprint, offset: offset + 0.02, from: y0, to: y0 + 0.05)
            for index in 0..<footprint.count where footprint.outward[index] != nil {
                let point = footprint.offset(index, offset + 0.01)
                builder.box(spec.columns ?? spec.timber, center: point.lifted((y0 + y1) / 2), size: [0.07, spec.storyHeight, 0.07])
            }
            openings(builder, footprint: footprint, spec: spec, offset: offset, y0: y0, y1: y1, tier: tier, doorEdge: doorEdge, random: &random)

            let isTop = tier == tiers - 1
            if isTop {
                let ridgeY = y1 + spec.roofRise
                roof(builder, footprint: footprint, spec: spec, wallOffset: offset, eaveY: y1, ridgeY: ridgeY)
                let ends = spec.pointed ? nil : ridgeEnds(footprint: footprint, wallOffset: offset, y: ridgeY)
                ornaments(builder, footprint: footprint, spec: spec, top: footprint.center.lifted(ridgeY), ends: ends.map { [$0.0, $0.1] } ?? [])
            } else {
                let nextOffset = offset - spec.tierInset
                if spec.skirts {
                    skirt(builder, footprint: footprint, spec: spec, wallOffset: offset, nextOffset: nextOffset, y: y1)
                }
                if spec.balcony {
                    balcony(builder, footprint: footprint, spec: spec, offset: nextOffset, y: y1)
                }
            }
        }
    }

    private static func mix3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    static func prism(_ builder: MeshBuilder, _ paint: Paint, footprint: Footprint, offset: Float, from y0: Float, to y1: Float) {
        walls(builder, paint, footprint: footprint, offset: offset, from: y0, to: y1)
        builder.cap(paint, footprint.points.indices.map { footprint.offset($0, offset).lifted(y1) })
    }

    static func walls(_ builder: MeshBuilder, _ paint: Paint, footprint: Footprint, offset: Float, from y0: Float, to y1: Float) {
        for index in 0..<footprint.count where footprint.exterior[index] {
            let next = footprint.next(index)
            let a = footprint.offset(index, offset), b = footprint.offset(next, offset)
            builder.quad(paint, a.lifted(y0), b.lifted(y0), b.lifted(y1), a.lifted(y1), outwardFrom: footprint.center.lifted((y0 + y1) / 2))
        }
    }

    static func bands(_ builder: MeshBuilder, _ paint: Paint, footprint: Footprint, offset: Float, from y0: Float, to y1: Float) {
        walls(builder, paint, footprint: footprint, offset: offset, from: y0, to: y1)
    }

    private static func openings(_ builder: MeshBuilder, footprint: Footprint, spec: BuildingSpec, offset: Float, y0: Float, y1: Float, tier: Int, doorEdge: Int?, random: inout SeededRandom) {
        let height = y1 - y0
        for index in 0..<footprint.count where footprint.exterior[index] {
            let next = footprint.next(index)
            let a = footprint.offset(index, offset), b = footprint.offset(next, offset)
            let length = simd_distance(a, b)
            guard length > 0.35 else {
                continue
            }
            let normal = footprint.edgeNormal(index)
            let push = normal * 0.022
            let direction = (b - a) / length
            let middle = (a + b) / 2 + push
            if tier == 0, index == doorEdge, let door = spec.door {
                let half = min(0.22, length * 0.3)
                let left = middle - direction * half, right = middle + direction * half
                builder.panel(.door, left.lifted(y0 + 0.02), right.lifted(y0 + 0.02), right.lifted(y0 + height * 0.78), left.lifted(y0 + height * 0.78), facing: normal.lifted(0))
                let clothLeft = left + normal * 0.012, clothRight = right + normal * 0.012
                builder.panel(door, clothLeft.lifted(y0 + height * 0.5), clothRight.lifted(y0 + height * 0.5), clothRight.lifted(y0 + height * 0.78), clothLeft.lifted(y0 + height * 0.78), facing: normal.lifted(0))
                if spec.lanterns {
                    for side in [left - direction * 0.1, right + direction * 0.1] {
                        let position = (side + normal * 0.08).lifted(y0 + height * 0.62)
                        builder.blob(.lanternRed, center: position, scale: [0.045, 0.065, 0.045])
                    }
                }
                continue
            }
            if spec.lattice, tier == 0 {
                // Koshi lattice across the whole front.
                let slats = Int(length / 0.07)
                let glowLeft = a + direction * 0.06 + normal * 0.01, glowRight = b - direction * 0.06 + normal * 0.01
                builder.panel(.windowGlow, glowLeft.lifted(y0 + 0.12), glowRight.lifted(y0 + 0.12), glowRight.lifted(y1 - 0.14), glowLeft.lifted(y1 - 0.14), facing: normal.lifted(0))
                for slat in 1..<max(slats, 2) {
                    let point = a + direction * (Float(slat) * length / Float(slats)) + normal * 0.03
                    builder.box(spec.timber == .blackWood ? .lattice : spec.timber, center: point.lifted((y0 + y1) / 2 - 0.01), size: [0.025, height - 0.26, 0.025], yaw: -atan2(direction.y, direction.x))
                }
                continue
            }
            let count = length > 1.3 ? 2 : 1
            for window in 0..<count {
                let t = (Float(window) + 0.5) / Float(count)
                let center = a + (b - a) * t + push
                let half = min(0.18, length * 0.18)
                let left = center - direction * half, right = center + direction * half
                let bottom = y0 + height * 0.38, top = y0 + height * 0.78
                let lit = random.chance(0.75)
                let paint: Paint = spec.windows == .shoji ? (lit ? .windowGlow : .shoji) : spec.windows
                builder.panel(paint, left.lifted(bottom), right.lifted(bottom), right.lifted(top), left.lifted(top), facing: normal.lifted(0))
                // Window frame bars.
                let frame = spec.timber == .gold ? Paint.blackWood : spec.timber
                builder.beam(frame, from: (left + normal * 0.01).lifted(bottom), to: (right + normal * 0.01).lifted(bottom), width: 0.03, height: 0.03)
                builder.beam(frame, from: (left + normal * 0.01).lifted(top), to: (right + normal * 0.01).lifted(top), width: 0.03, height: 0.03)
                builder.beam(frame, from: (center + normal * 0.01).lifted(bottom), to: (center + normal * 0.01).lifted(top), width: 0.02, height: 0.02)
            }
        }
    }

    // Bottom to top, horizontal moves linearly while height follows t^curve, which bends the roof into a concave sweep.
    static func sweep(_ builder: MeshBuilder, _ paint: Paint, bottom: (SIMD3<Float>, SIMD3<Float>), top: (SIMD3<Float>, SIMD3<Float>), curve: Float, steps: Int = 3) {
        func point(_ low: SIMD3<Float>, _ high: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
            let horizontal = low.xz + (high.xz - low.xz) * t
            return horizontal.lifted(low.y + (high.y - low.y) * pow(t, curve))
        }
        for step in 0..<steps {
            let t0 = Float(step) / Float(steps)
            let t1 = Float(step + 1) / Float(steps)
            let a = point(bottom.0, top.0, t0), b = point(bottom.1, top.1, t0)
            let c = point(bottom.1, top.1, t1), d = point(bottom.0, top.0, t1)
            let below = (a + b + c + d) / 4 - SIMD3<Float>(0, 4, 0)
            builder.quad(paint, a, b, c, d, outwardFrom: below)
        }
    }

    private static func roof(_ builder: MeshBuilder, footprint: Footprint, spec: BuildingSpec, wallOffset: Float, eaveY: Float, ridgeY: Float) {
        let eaveOffset = wallOffset + spec.overhang
        // Corners upturn a little at the eave, like a real Japanese roof.
        func eave(_ index: Int) -> SIMD3<Float> {
            if footprint.outward[index] == nil {
                // Where three cells of one building meet, the roof rises to a small peak.
                return footprint.points[index].lifted(ridgeY + spec.roofRise * 0.22)
            }
            return footprint.offset(index, eaveOffset).lifted(eaveY + spec.overhang * 0.12)
        }
        let top = footprint.center.lifted(ridgeY)
        let ridge = spec.pointed ? nil : ridgeEnds(footprint: footprint, wallOffset: wallOffset, y: ridgeY)
        func ridgeTop(_ index: Int) -> SIMD3<Float> {
            guard let ridge else {
                return top
            }
            return simd_dot(footprint.points[index] - footprint.center, ridge.axis) < 0 ? ridge.0 : ridge.1
        }
        if let ridge {
            builder.beam(spec.ridge ?? .stoneDark, from: ridge.0 + [0, 0.03, 0], to: ridge.1 + [0, 0.03, 0], width: 0.1, height: 0.08)
        }
        for index in 0..<footprint.count {
            let next = footprint.next(index)
            let a = eave(index), b = eave(next)
            if footprint.exterior[index] {
                sweep(builder, spec.roof, bottom: (a, b), top: (ridgeTop(index), ridgeTop(next)), curve: spec.curve)
                // Fascia and soffit.
                let down = SIMD3<Float>(0, -spec.fascia, 0)
                builder.quad(spec.soffit, a, b, b + down, a + down, outwardFrom: footprint.center.lifted(eaveY))
                let wallA = footprint.offset(index, wallOffset).lifted(eaveY), wallB = footprint.offset(next, wallOffset).lifted(eaveY)
                builder.quad(spec.soffit, a + down, b + down, wallB, wallA, outwardFrom: footprint.center.lifted(eaveY + 3))
            } else {
                let middle = ((footprint.points[index] + footprint.points[next]) / 2).lifted(ridgeY)
                sweep(builder, spec.roof, bottom: (a, a), top: (top, middle), curve: spec.curve)
                sweep(builder, spec.roof, bottom: (b, b), top: (middle, top), curve: spec.curve)
                builder.beam(spec.ridge ?? .stoneDark, from: top + [0, 0.03, 0], to: middle + [0, 0.03, 0], width: 0.1, height: 0.08)
            }
        }
    }

    // A single-cell roof gets a short ridge along its long axis, so it reads as a hipped roof, not a cone.
    static func ridgeEnds(footprint: Footprint, wallOffset: Float, y: Float) -> (SIMD3<Float>, SIMD3<Float>, axis: SIMD2<Float>)? {
        guard !footprint.exterior.contains(false) else {
            return nil
        }
        var axis = SIMD2<Float>(1, 0)
        var longest: Float = 0
        for i in footprint.points.indices {
            for j in footprint.points.indices where j > i {
                let delta = footprint.points[j] - footprint.points[i]
                let length = simd_length(delta)
                if length > longest {
                    longest = length
                    axis = delta / length
                }
            }
        }
        let half = max(0, longest / 2 + wallOffset) * 0.45
        let center = footprint.center
        return ((center - axis * half).lifted(y), (center + axis * half).lifted(y), axis)
    }

    private static func skirt(_ builder: MeshBuilder, footprint: Footprint, spec: BuildingSpec, wallOffset: Float, nextOffset: Float, y: Float) {
        for index in 0..<footprint.count where footprint.exterior[index] {
            let next = footprint.next(index)
            let eaveA = footprint.offset(index, wallOffset + spec.skirtOverhang).lifted(y - 0.06)
            let eaveB = footprint.offset(next, wallOffset + spec.skirtOverhang).lifted(y - 0.06)
            let topA = footprint.offset(index, nextOffset).lifted(y + spec.skirtRise)
            let topB = footprint.offset(next, nextOffset).lifted(y + spec.skirtRise)
            sweep(builder, spec.roof, bottom: (eaveA, eaveB), top: (topA, topB), curve: spec.curve, steps: 2)
            let down = SIMD3<Float>(0, -spec.fascia, 0)
            builder.quad(spec.soffit, eaveA, eaveB, eaveB + down, eaveA + down, outwardFrom: footprint.center.lifted(y))
            let wallA = footprint.offset(index, wallOffset).lifted(y - 0.06), wallB = footprint.offset(next, wallOffset).lifted(y - 0.06)
            builder.quad(spec.soffit, eaveA + down, eaveB + down, wallB, wallA, outwardFrom: footprint.center.lifted(y + 3))
        }
    }

    private static func balcony(_ builder: MeshBuilder, footprint: Footprint, spec: BuildingSpec, offset: Float, y: Float) {
        for index in 0..<footprint.count where footprint.exterior[index] {
            let next = footprint.next(index)
            let innerA = footprint.offset(index, offset), innerB = footprint.offset(next, offset)
            let outerA = footprint.offset(index, offset + 0.26), outerB = footprint.offset(next, offset + 0.26)
            builder.quad(spec.timber, innerA.lifted(y + 0.02), innerB.lifted(y + 0.02), outerB.lifted(y + 0.02), outerA.lifted(y + 0.02), outwardFrom: footprint.center.lifted(y - 3))
            builder.quad(spec.timber, outerA.lifted(y - 0.04), outerB.lifted(y - 0.04), outerB.lifted(y + 0.02), outerA.lifted(y + 0.02), outwardFrom: footprint.center.lifted(y))
            builder.beam(spec.timber, from: outerA.lifted(y + 0.22), to: outerB.lifted(y + 0.22), width: 0.04, height: 0.04)
            builder.beam(spec.timber, from: outerA.lifted(y + 0.1), to: outerB.lifted(y + 0.1), width: 0.02, height: 0.02)
            if footprint.outward[index] != nil {
                builder.box(spec.timber, center: outerA.lifted(y + 0.12), size: [0.04, 0.22, 0.04])
            }
        }
    }

    private static func ornaments(_ builder: MeshBuilder, footprint: Footprint, spec: BuildingSpec, top: SIMD3<Float>, ends: [SIMD3<Float>]) {
        // Onigawara ridge-end tiles, or gold shachihoko on castles.
        for end in ends {
            if spec.shachi {
                builder.blob(.gold, center: end + [0, 0.13, 0], scale: [0.05, 0.12, 0.05])
                builder.cone(.gold, base: end + [0, 0.2, 0], tip: end + [0, 0.3, 0] + (end - top) * 0.3, radius: 0.04, sides: 4)
            } else if spec.ridge == nil {
                builder.box(.stoneDark, center: end + [0, 0.08, 0], size: [0.12, 0.14, 0.12])
            }
        }
        if ends.isEmpty, spec.shachi {
            builder.blob(.gold, center: top + [0, 0.12, 0], scale: [0.05, 0.12, 0.05])
        }
        if spec.chigi {
            let direction = simd_normalize(footprint.points[0] - footprint.center)
            for side: Float in [-1, 1] {
                let base = top + (direction * 0.25 * side).lifted(0)
                builder.beam(spec.ridge ?? .darkWood, from: base - (direction * 0.1 * side).lifted(0), to: base + (direction * 0.12 * side).lifted(0.35), width: 0.04, height: 0.02)
                builder.beam(spec.ridge ?? .darkWood, from: base - [0, 0, 0] + (direction.perpendicular * 0.12).lifted(0), to: base + (direction.perpendicular * 0.18).lifted(0.32), width: 0.04, height: 0.02)
            }
            for step in -1...1 {
                let base = top + (direction * Float(step) * 0.12).lifted(0.04)
                builder.beam(.gold, from: base - (direction.perpendicular * 0.1).lifted(0), to: base + (direction.perpendicular * 0.1).lifted(0), width: 0.05, height: 0.05)
            }
        }
        if spec.spire {
            builder.cylinder(.bronze, from: top, to: top + [0, 1.3, 0], radius: 0.035)
            for ring in 0..<7 {
                let y = 0.2 + Float(ring) * 0.13
                builder.frustum(.bronze, from: top + [0, y, 0], to: top + [0, y + 0.03, 0], radiusA: 0.09, radiusB: 0.08, sides: 8, caps: true)
            }
            builder.blob(.gold, center: top + [0, 1.38, 0], scale: SIMD3(repeating: 0.07))
        }
    }
}
