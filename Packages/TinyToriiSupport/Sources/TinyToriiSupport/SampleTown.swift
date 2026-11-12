import simd

// Builds a little town by itself, for the CLI and as a starting point in the app.
public extension Town {
    static func sample(seed: UInt32 = 1) -> Town {
        var town = Town(gridSeed: seed)
        var random = SeededRandom(seed: seed &* 31 &+ 7)
        let grid = town.grid
        let count = grid.cells.count
        func distance(_ cell: Int, _ point: SIMD2<Float>) -> Float {
            simd_distance(grid.cells[cell].center, point)
        }
        func nearest(_ point: SIMD2<Float>) -> Int {
            (0..<count).min { distance($0, point) < distance($1, point) }!
        }
        func isFree(_ cell: Int) -> Bool {
            town.cells[cell].item == nil && town.cells[cell].ground != .water
        }
        let isCoast: [Bool] = (0..<count).map { grid.cells[$0].neighbors.contains(nil) }

        // Castle hill.
        let hillAngle = random.range(0, 2 * .pi)
        let hillCenter = SIMD2<Float>(cos(hillAngle), sin(hillAngle)) * grid.radius * 0.42
        for cell in 0..<count {
            let d = distance(cell, hillCenter)
            let elevation = Int(max(0, 4.6 - d / 5.95))
            town.cells[cell].elevation = min(elevation, 4)
        }
        let castleCell = nearest(hillCenter)
        town.place(.castle, style: random.int(3), at: castleCell)
        if let wing = grid.neighborSet(of: castleCell).first(where: { town.cells[$0].elevation == town.cells[castleCell].elevation }) {
            town.stretch(from: castleCell, to: wing)
            town.shrink(wing)
            town.shrink(wing)
        }
        for neighbor in grid.neighborSet(of: castleCell) where isFree(neighbor) {
            if random.chance(0.5) {
                town.place(.pine, style: 0, at: neighbor)
            } else {
                town.place(.paintGravel, style: 0, at: neighbor)
            }
        }

        // Paths: walks from the center outward.
        var pathCells: [Int] = []
        let start = nearest(.zero)
        for _ in 0..<5 {
            var cell = start
            var heading = random.range(0, 2 * .pi)
            for _ in 0..<14 {
                if town.cells[cell].elevation <= 1, town.cells[cell].item == nil {
                    town.cells[cell].ground = .path
                    pathCells.append(cell)
                }
                let target = grid.cells[cell].center + SIMD2(cos(heading), sin(heading)) * 3
                let next = grid.neighborSet(of: cell).min { distance($0, target) < distance($1, target) }
                guard let next, !isCoast[next] else {
                    break
                }
                cell = next
                heading += random.signed() * 0.5
            }
        }
        let pathSet = Set(pathCells)

        // Shrine with a torii tunnel, foxes and lanterns.
        let shrineAngle = hillAngle + .pi * random.range(0.6, 0.9)
        let shrineCenter = SIMD2<Float>(cos(shrineAngle), sin(shrineAngle)) * grid.radius * 0.5
        let shrineCell = nearest(shrineCenter)
        town.cells[shrineCell].elevation = 1
        town.place(.shrine, style: random.int(3), at: shrineCell)
        var approach = shrineCell
        let toCenter = -simd_normalize(shrineCenter)
        for step in 0..<5 {
            let target = grid.cells[approach].center + toCenter * 7.7
            guard let next = grid.neighborSet(of: approach).filter({ isFree($0) || town.cells[$0].ground == .path }).min(by: { distance($0, target) < distance($1, target) }) else {
                break
            }
            approach = next
            town.cells[approach].ground = .gravel
            switch step {
            case 0: town.place(.foxStatue, style: 0, at: approach)
            case 1, 2: town.place(.torii, style: 0, at: approach)
            case 3: town.place(.stoneLantern, style: 0, at: approach)
            default: town.place(.greatTorii, style: 0, at: approach)
            }
            if let item = town.cells[approach].item {
                var rotated = item
                let direction = toCenter
                rotated.rotation = atan2(direction.y, direction.x) + .pi / 2
                town.cells[approach].item = rotated
            }
            town.cells[approach].elevation = 0
        }
        for neighbor in grid.neighborSet(of: shrineCell) where isFree(neighbor) {
            town.place(random.chance(0.5) ? .sugi : .stoneLantern, style: 0, at: neighbor)
        }

        // Temple garden with a pagoda, zen garden and pond.
        let templeAngle = hillAngle - .pi * random.range(0.55, 0.8)
        let templeCenter = SIMD2<Float>(cos(templeAngle), sin(templeAngle)) * grid.radius * 0.45
        let templeCell = nearest(templeCenter)
        if isFree(templeCell) {
            town.cells[templeCell].elevation = 0
            town.place(.temple, style: random.int(3), at: templeCell)
            let around = grid.neighborSet(of: templeCell).filter(isFree)
            if around.count >= 3 {
                town.stretch(from: templeCell, to: around[0])
                town.place(.pagoda, style: random.int(3), at: around[1])
                town.cells[around[2]].ground = .gravel
                town.place(.zenGarden, style: 0, at: around[2])
            }
            for neighbor in grid.neighborSet(of: templeCell) where isFree(neighbor) {
                town.place(random.pick([Kind.momiji, .stoneLantern, .azalea, .stones]), style: random.int(3), at: neighbor)
            }
        }

        // A pond with a drum bridge.
        let pondCenter = SIMD2<Float>(cos(templeAngle + 0.6), sin(templeAngle + 0.6)) * grid.radius * 0.25
        let pondCell = nearest(pondCenter)
        var pond = [pondCell] + grid.neighborSet(of: pondCell)
        pond = pond.filter { isFree($0) && town.cells[$0].elevation == 0 }
        for cell in pond {
            town.cells[cell].ground = .water
        }
        if let bridgeCell = pond.first {
            town.place(.bridge, style: 0, at: bridgeCell)
        }
        for cell in pond.dropFirst() {
            if random.chance(0.3) {
                town.place(.koiPond, style: random.int(3), at: cell)
            } else if random.chance(0.6) {
                town.place(.koi, style: random.int(3), at: cell)
            }
        }
        // Cranes and frogs by the water.
        for cell in Set(pond.flatMap { grid.neighborSet(of: $0) }) where isFree(cell) && random.chance(0.35) {
            town.place(random.chance(0.5) ? .crane : .frog, style: random.int(2), at: cell)
        }

        // Houses along the paths.
        for cell in 0..<count where isFree(cell) && !isCoast[cell] && town.cells[cell].ground != .path && town.cells[cell].elevation <= 1 {
            let nearPath = grid.neighborSet(of: cell).contains { pathSet.contains($0) }
            let fromCenter = simd_length(grid.cells[cell].center) / grid.radius
            if nearPath, random.chance(0.6) {
                let kind: Kind = fromCenter < 0.35 ? random.pick([.machiya, .machiya, .ryokan, .kura, .teahouse]) : random.pick([.machiya, .minka, .minka, .kura])
                town.place(kind, style: random.int(kind.styles.count), at: cell)
                if kind == .machiya || kind == .ryokan, random.chance(0.5) {
                    town.grow(cell)
                }
                if kind.isBuilding, random.chance(0.45), let neighbor = grid.neighborSet(of: cell).first(where: { isFree($0) && town.cells[$0].ground != .path && town.cells[$0].elevation == town.cells[cell].elevation && !isCoast[$0] }) {
                    town.stretch(from: cell, to: neighbor)
                }
            }
        }
        // Cats in town, a fox by the shrine, tanuki at the edges.
        for cell in pathCells where town.cells[cell].item == nil && random.chance(0.06) {
            town.place(.cat, style: random.int(3), at: cell)
        }
        if let foxCell = grid.neighborSet(of: shrineCell).first(where: isFree) {
            town.place(.fox, style: 0, at: foxCell)
        }
        for cell in pathCells where town.cells[cell].item == nil && random.chance(0.03) {
            town.place(.tanuki, style: 1, at: cell)
        }

        // Lanterns on the paths.
        for cell in pathCells where town.cells[cell].item == nil && random.chance(0.12) {
            town.place(random.chance(0.5) ? .paperLantern : .stoneLantern, style: random.int(3), at: cell)
        }

        // Trees, a bamboo grove, paddies and beaches.
        let groveAngle = random.range(0, 2 * .pi)
        let groveCenter = SIMD2<Float>(cos(groveAngle), sin(groveAngle)) * grid.radius * 0.75
        for cell in 0..<count where isFree(cell) {
            let fromCenter = simd_length(grid.cells[cell].center) / grid.radius
            if isCoast[cell] {
                town.cells[cell].ground = .sand
                if random.chance(0.2) {
                    town.place(.pine, style: 2, at: cell)
                }
                continue
            }
            if distance(cell, groveCenter) < 4.5 {
                town.place(.bamboo, style: random.chance(0.8) ? 0 : 1, at: cell)
                continue
            }
            if fromCenter > 0.7, town.cells[cell].elevation == 0, random.chance(0.45), town.cells[cell].ground == .grass {
                town.cells[cell].ground = .paddy
                continue
            }
            if town.cells[cell].ground == .path {
                continue
            }
            if random.chance(0.28) {
                let kind = random.pick([Kind.sakura, .sakura, .sakura, .momiji, .pine, .ume, .ginkgo, .willow, .azalea, .stones])
                town.place(kind, style: random.int(kind.styles.count), at: cell)
                if random.chance(0.4) {
                    town.grow(cell)
                }
            } else if random.chance(0.15) {
                town.cells[cell].ground = .moss
            }
        }
        return town
    }
}
