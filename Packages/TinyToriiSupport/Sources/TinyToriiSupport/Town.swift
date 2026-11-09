import Foundation
import simd

public struct Item: Codable, Sendable, Equatable {
    public var kind: Kind
    public var style: Int
    public var level: Int
    // Cells with the same group are one building.
    public var group: Int
    public var seed: UInt32
    // Radians, for things that face a way (torii, foxes, bridges).
    public var rotation: Float
}

public struct CellState: Codable, Sendable, Equatable {
    public var elevation: Int = 0
    public var ground: Ground = .grass
    public var item: Item?
}

public struct Town: Sendable {
    public static let elevationStep: Float = 0.45
    public static let maxElevation = 6

    public let grid: Grid
    public let gridSeed: UInt32
    public var cells: [CellState]
    public var nextGroup = 1

    public init(gridSeed: UInt32 = 1) {
        self.gridSeed = gridSeed
        grid = Grid(seed: gridSeed)
        cells = Array(repeating: CellState(), count: grid.cells.count)
    }

    public func groundHeight(_ cell: Int) -> Float {
        let state = cells[cell]
        let base = Float(state.elevation) * Self.elevationStep
        switch state.ground {
        case .water: return base - 0.22
        case .paddy: return base - 0.06
        default: return base
        }
    }

    // The ground height for walking and placing: water counts as its banks.
    public func standingHeight(_ cell: Int) -> Float {
        Float(cells[cell].elevation) * Self.elevationStep
    }

    // Cells whose meshes depend on this cell: itself, its neighbors and its building.
    public func affectedCells(by cell: Int) -> Set<Int> {
        var result: Set<Int> = [cell]
        for neighbor in grid.neighborSet(of: cell) {
            result.insert(neighbor)
        }
        if let group = cells[cell].item?.group {
            for (index, state) in cells.enumerated() where state.item?.group == group {
                result.insert(index)
            }
        }
        return result
    }

    // Whether two cells draw as one building: same group, level and elevation.
    public func joins(_ a: Int, _ b: Int?) -> Bool {
        guard let b, let first = cells[a].item, let second = cells[b].item else {
            return false
        }
        return first.kind.isBuilding && first.group == second.group && first.level == second.level && cells[a].elevation == cells[b].elevation
    }

    // MARK: - Editing. Each returns the cells to rebuild.

    @discardableResult
    public mutating func place(_ kind: Kind, style: Int, at cell: Int, rotation: Float? = nil) -> Set<Int> {
        let before = affectedCells(by: cell)
        if let ground = kind.paint {
            cells[cell].ground = ground
            if ground == .water, let item = cells[cell].item, item.kind.impliedGround != .water {
                cells[cell].item = nil
            }
            return before.union(affectedCells(by: cell))
        }
        var random = SeededRandom(seed: UInt32(cell) &* 7_919 &+ UInt32(nextGroup) &* 104_729)
        let item = Item(kind: kind, style: min(style, kind.styles.count - 1), level: kind.defaultLevel, group: nextGroup, seed: random.nextUInt32(), rotation: rotation ?? defaultRotation(for: cell, random: &random))
        nextGroup += 1
        cells[cell].item = item
        if let ground = kind.impliedGround {
            cells[cell].ground = kind == .zenGarden && item.style == 1 ? .sand : ground
        } else if cells[cell].ground == .water || (kind.isBuilding && cells[cell].ground == .paddy) {
            cells[cell].ground = .grass
        }
        return before.union(affectedCells(by: cell))
    }

    // Faces along the cell's longest edge, so gates and bridges sit naturally in the grid.
    func defaultRotation(for cell: Int, random: inout SeededRandom) -> Float {
        let points = grid.polygon(of: cell)
        var best: Float = 0
        var bestLength: Float = 0
        for index in points.indices {
            let edge = points[(index + 1) % points.count] - points[index]
            let length = simd_length(edge)
            if length > bestLength {
                bestLength = length
                best = atan2(edge.y, edge.x)
            }
        }
        return best + (random.chance(0.5) ? .pi : 0)
    }

    @discardableResult
    public mutating func grow(_ cell: Int) -> Set<Int> {
        if var item = cells[cell].item, item.level < item.kind.maxLevel {
            item.level += 1
            cells[cell].item = item
        } else if cells[cell].item == nil, cells[cell].elevation < Self.maxElevation {
            cells[cell].elevation += 1
        } else {
            return []
        }
        return affectedCells(by: cell)
    }

    @discardableResult
    public mutating func shrink(_ cell: Int) -> Set<Int> {
        if var item = cells[cell].item, item.level > 1 {
            item.level -= 1
            cells[cell].item = item
        } else if cells[cell].item == nil, cells[cell].elevation > 0 {
            cells[cell].elevation -= 1
        } else {
            return []
        }
        return affectedCells(by: cell)
    }

    @discardableResult
    public mutating func remove(_ cell: Int) -> Set<Int> {
        let before = affectedCells(by: cell)
        if let item = cells[cell].item {
            cells[cell].item = nil
            if item.kind.impliedGround != nil {
                cells[cell].ground = .grass
            }
        } else if cells[cell].ground != .grass {
            cells[cell].ground = .grass
        } else if cells[cell].elevation > 0 {
            cells[cell].elevation -= 1
        } else {
            return []
        }
        return before.union(affectedCells(by: cell))
    }

    @discardableResult
    public mutating func rotate(_ cell: Int) -> Set<Int> {
        guard var item = cells[cell].item else {
            return []
        }
        item.rotation += .pi / 3
        cells[cell].item = item
        return [cell]
    }

    @discardableResult
    public mutating func restyle(_ cell: Int) -> Set<Int> {
        guard let item = cells[cell].item else {
            return []
        }
        let count = item.kind.styles.count
        let group = item.group
        for index in cells.indices where cells[index].item?.group == group {
            cells[index].item?.style = (item.style + 1) % count
        }
        return affectedCells(by: cell)
    }

    // Copies a cell's building, tree or ground into a neighbor. Buildings stay one building.
    @discardableResult
    public mutating func stretch(from source: Int, to target: Int) -> Set<Int> {
        guard source != target else {
            return []
        }
        let before = affectedCells(by: target)
        let state = cells[source]
        if var item = state.item {
            if !item.kind.isBuilding {
                var random = SeededRandom(seed: item.seed &+ UInt32(target) &* 31)
                item.seed = random.nextUInt32()
                item.group = nextGroup
                nextGroup += 1
            }
            cells[target].item = item
            cells[target].elevation = state.elevation
        }
        if state.item == nil || state.item?.kind.impliedGround != nil {
            cells[target].ground = state.ground
        }
        if state.item == nil {
            cells[target].elevation = state.elevation
        }
        return before.union(affectedCells(by: target))
    }
}

// MARK: - Saving

public struct TownFile: Codable, Sendable {
    public var version = 1
    public var gridSeed: UInt32
    public var nextGroup: Int
    public var cells: [CellState]
}

public extension Town {
    var file: TownFile {
        TownFile(gridSeed: gridSeed, nextGroup: nextGroup, cells: cells)
    }

    init(file: TownFile) {
        self.init(gridSeed: file.gridSeed)
        if file.cells.count == cells.count {
            cells = file.cells
        }
        nextGroup = file.nextGroup
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    init(data: Data) throws {
        self.init(file: try JSONDecoder().decode(TownFile.self, from: data))
    }
}
