import Foundation
import GeometryLite3D
import simd
import Testing
@testable import TinyToriiSupport

@Suite struct GridTests {
    let grid = Grid(seed: 3)

    @Test func cellsArePolygons() {
        #expect(grid.cells.count > 300)
        for cell in grid.cells {
            #expect(cell.polygon.count >= 3)
            #expect(cell.neighbors.count == cell.polygon.count)
        }
    }

    @Test func neighborsAreMutual() {
        for (index, cell) in grid.cells.enumerated() {
            for neighbor in cell.neighbors.compactMap(\.self) {
                #expect(grid.cells[neighbor].neighbors.contains(index))
            }
        }
    }

    @Test func cellLookupFindsItsOwnCenter() {
        for index in stride(from: 0, to: grid.cells.count, by: 7) {
            #expect(grid.cell(at: grid.cells[index].center) == index)
        }
    }

    @Test func seedsAreDeterministic() {
        #expect(Grid(seed: 3).vertices == grid.vertices)
    }
}

@Suite struct TownTests {
    var town = Town(gridSeed: 2)
    var center: Int {
        town.grid.cells.indices.min { simd_length(town.grid.cells[$0].center) < simd_length(town.grid.cells[$1].center) }!
    }

    @Test mutating func placeGrowShrinkRemove() {
        let cell = center
        town.place(.machiya, style: 1, at: cell)
        #expect(town.cells[cell].item?.kind == .machiya)
        #expect(town.cells[cell].item?.style == 1)
        town.grow(cell)
        town.grow(cell)
        town.grow(cell)
        #expect(town.cells[cell].item?.level == Kind.machiya.maxLevel)
        town.shrink(cell)
        #expect(town.cells[cell].item?.level == Kind.machiya.maxLevel - 1)
        town.remove(cell)
        #expect(town.cells[cell].item == nil)
    }

    @Test mutating func growingEmptyGroundRaisesIt() {
        let cell = center
        town.grow(cell)
        town.grow(cell)
        #expect(town.cells[cell].elevation == 2)
        town.remove(cell)
        #expect(town.cells[cell].elevation == 1)
    }

    @Test mutating func stretchingJoinsABuilding() {
        let cell = center
        let neighbor = town.grid.neighborSet(of: cell)[0]
        town.place(.castle, style: 0, at: cell)
        town.stretch(from: cell, to: neighbor)
        #expect(town.joins(cell, neighbor))
        let footprint = Footprint(town: town, cell: cell)
        #expect(footprint.exterior.contains(false))
        town.grow(neighbor)
        #expect(!town.joins(cell, neighbor))
    }

    @Test mutating func stretchingATreeMakesANewTree() {
        let cell = center
        let neighbor = town.grid.neighborSet(of: cell)[0]
        town.place(.sakura, style: 0, at: cell)
        town.stretch(from: cell, to: neighbor)
        #expect(town.cells[neighbor].item?.kind == .sakura)
        #expect(town.cells[neighbor].item?.seed != town.cells[cell].item?.seed)
    }

    @Test mutating func paintingWaterClearsBuildings() {
        let cell = center
        town.place(.minka, style: 0, at: cell)
        town.place(.paintWater, style: 0, at: cell)
        #expect(town.cells[cell].ground == .water)
        #expect(town.cells[cell].item == nil)
    }

    @Test func savingRoundTrips() throws {
        let sample = Town.sample(seed: 4)
        let loaded = try Town(data: sample.encoded())
        #expect(loaded.cells == sample.cells)
        #expect(loaded.nextGroup == sample.nextGroup)
    }

    @Test func everyKindHasAThumbnail() {
        for kind in Kind.allCases {
            #expect(kind.thumbnailURL != nil, "\(kind)")
        }
    }

    @Test func sampleTownHasACastle() {
        let sample = Town.sample(seed: 9)
        #expect(sample.cells.contains { $0.item?.kind == .castle })
        #expect(sample.cells.contains { $0.item?.kind == .torii || $0.item?.kind == .greatTorii })
    }
}

@MainActor
@Suite struct SceneTests {
    @Test func pickingStraightDownFindsTheCell() {
        let scene = TownScene(town: Town(gridSeed: 5))
        for cell in stride(from: 0, to: scene.cellCount, by: 11) {
            let center = scene.town.grid.cells[cell].center
            let ray = Ray3D(origin: center.lifted(50), direction: [0, -1, 0])
            #expect(scene.pick(ray: ray) == cell)
        }
    }

    @Test func pickingHitsTheSideOfATallBuilding() {
        var town = Town(gridSeed: 5)
        let cell = town.grid.cells.indices.min { simd_length(town.grid.cells[$0].center) < simd_length(town.grid.cells[$1].center) }!
        town.place(.castle, style: 0, at: cell)
        let scene = TownScene(town: town)
        let center = town.grid.cells[cell].center
        // A level ray at castle height, coming from far away, hits the castle before anything behind it.
        let ray = Ray3D(origin: [center.x - 30, 2, center.y], direction: [1, 0, 0])
        #expect(scene.pick(ray: ray) == cell)
    }

    @Test func editsRebuildAndUndo() {
        let model = TownModel(town: Town(gridSeed: 6), persists: false)
        let cell = 10
        model.choose(.pagoda)
        model.apply(at: cell)
        #expect(model.scene.town.cells[cell].item?.kind == .pagoda)
        #expect(model.canUndo)
        model.undo()
        #expect(model.scene.town.cells[cell].item == nil)
        model.redo()
        #expect(model.scene.town.cells[cell].item?.kind == .pagoda)
    }

    @Test func stretchToolExtendsFromTheSelectedBuilding() {
        let model = TownModel(town: Town(gridSeed: 6), persists: false)
        let cell = model.scene.town.grid.cells.indices.first { !model.scene.town.grid.cells[$0].neighbors.contains(nil) }!
        let neighbor = model.scene.town.grid.neighborSet(of: cell)[0]
        model.choose(.ryokan)
        model.apply(at: cell)
        model.choose(tool: .stretch)
        model.apply(at: cell)
        model.apply(at: neighbor)
        #expect(model.scene.town.joins(cell, neighbor))
    }

    @Test func aDragPaintsManyCellsAndUndoesAtOnce() {
        let model = TownModel(town: Town(gridSeed: 6), persists: false)
        let start = 40
        let path = [start] + model.scene.town.grid.neighborSet(of: start).prefix(3)
        model.choose(.paintPath)
        #expect(model.toolPaintsWithDrags)
        model.beginStroke(at: path[0])
        for cell in path.dropFirst() {
            model.continueStroke(at: cell)
        }
        model.endStroke()
        #expect(path.allSatisfy { model.scene.town.cells[$0].ground == .path })
        model.undo()
        #expect(path.allSatisfy { model.scene.town.cells[$0].ground == .grass })
    }

    @Test func aStretchDragGrowsABuilding() {
        let model = TownModel(town: Town(gridSeed: 6), persists: false)
        let town = model.scene.town
        let cell = town.grid.cells.indices.first { !town.grid.cells[$0].neighbors.contains(nil) }!
        let first = town.grid.neighborSet(of: cell)[0]
        let second = town.grid.neighborSet(of: first).first { $0 != cell && !town.grid.neighborSet(of: cell).contains($0) }!
        model.choose(.machiya)
        model.apply(at: cell)
        model.choose(tool: .stretch)
        model.beginStroke(at: cell)
        model.continueStroke(at: first)
        model.continueStroke(at: second)
        model.endStroke()
        #expect(model.scene.town.joins(cell, first))
        #expect(model.scene.town.joins(first, second))
    }

    @Test func randomEditsMakeFiniteMeshes() {
        var town = Town(gridSeed: 8)
        var random = SeededRandom(seed: 42)
        let kinds = Kind.allCases
        let count = town.grid.cells.count
        for _ in 0..<1_500 {
            let cell = random.int(count)
            switch random.int(6) {
            case 0, 1: town.place(random.pick(kinds), style: random.int(4), at: cell)
            case 2: town.grow(cell)
            case 3: town.shrink(cell)
            case 4: town.remove(cell)
            default:
                if let neighbor = town.grid.neighborSet(of: cell).first {
                    town.stretch(from: cell, to: neighbor)
                }
            }
        }
        for cell in 0..<count {
            let builder = MeshBuilder()
            GroundMesher.build(builder, town: town, cell: cell)
            if let item = town.cells[cell].item {
                if item.kind.isBuilding {
                    BuildingMesher.build(builder, town: town, cell: cell, item: item)
                } else if item.kind.category == .trees {
                    TreeMesher.build(builder, item: item)
                } else {
                    PropMesher.build(builder, item: item, polygon: town.grid.polygon(of: cell).map { $0 - town.grid.cells[cell].center }, joined: town.grid.cells[cell].neighbors.map { _ in false })
                }
            }
            #expect(builder.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, "cell \(cell)")
        }
        // And the scene builds it all.
        let scene = TownScene(town: town)
        #expect(scene.cellCount == count)
    }

    @Test func writingBackTheCameraMatrixSettles() {
        let model = TownModel(town: Town(gridSeed: 6), persists: false)
        let pose = model.rtsPose
        // What SceneView does: write back the matrix it was given.
        model.cameraMatrix = model.cameraMatrix
        #expect(model.rtsPose == pose)
        // A real orbit still moves the camera.
        model.cameraMatrix = TownCamera.orbit(yaw: 1.2, pitch: 0.5, distance: 30)
        #expect(abs(model.rtsPose.distance - 30) < 0.01)
        #expect(abs(model.rtsPose.yaw - 1.2) < 0.01)
    }

    @Test func walkerStaysOutOfBuildings() {
        let scene = TownScene(town: Town.sample(seed: 3))
        let explorer = Explorer(scene: scene)
        explorer.start()
        explorer.isStrolling = true
        for step in 0..<1_800 {
            explorer.sceneView(updateAtTime: Float(step) / 30, deltaTime: 1 / 30)
            let position = explorer.cameraNode.transform.columns.3
            if let cell = scene.town.grid.cell(at: [position.x, position.z]) {
                #expect(!(scene.town.cells[cell].item?.kind.blocksWalking ?? false))
            }
        }
    }
}
