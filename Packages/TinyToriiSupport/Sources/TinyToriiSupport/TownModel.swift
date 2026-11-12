import Foundation
import GeometryLite3D
import Interaction3D
import Observation
import SceneSprockets
import simd

public enum Tool: String, CaseIterable, Identifiable, Sendable {
    case place = "Place"
    case grow = "Grow"
    case shrink = "Shrink"
    case stretch = "Stretch"
    case rotate = "Rotate"
    case restyle = "Restyle"
    case remove = "Remove"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .place: "plus.circle"
        case .grow: "arrow.up.circle"
        case .shrink: "arrow.down.circle"
        case .stretch: "arrow.left.and.right.circle"
        case .rotate: "arrow.clockwise.circle"
        case .restyle: "paintpalette"
        case .remove: "trash.circle"
        }
    }

    public var help: String {
        switch self {
        case .place: "Tap a cell to place the chosen thing. Drag to paint ground."
        case .grow: "Tap to add a story, grow a tree, or raise the ground."
        case .shrink: "Tap to take a story away, or lower the ground."
        case .stretch: "Drag from a building, tree or patch of ground across its neighbors to stretch it."
        case .rotate: "Tap to turn gates, foxes and bridges."
        case .restyle: "Tap to cycle a thing's style."
        case .remove: "Tap or drag to clear cells."
        }
    }
}

public enum Mode: String, Sendable {
    case build
    case explore
}

@MainActor
@Observable
public final class TownModel {
    public let scene: TownScene
    public var tool: Tool = .place
    public var kind: Kind = .machiya
    public var style = 0
    public var category: Category = .buildings
    public var mode: Mode = .build {
        didSet { modeChanged(from: oldValue) }
    }
    public var time: TimeOfDay = .day {
        didSet { scene.setTime(time) }
    }
    // The build camera: Interaction3D's RTS pose (keys and edge panning move its target), shared with SceneView's
    // mouse orbit and zoom through `cameraMatrix`.
    // Clamp in the setter, not in a didSet: with @Observable, writing the property from its own didSet re-enters
    // didSet, and Float rounding can keep the clamped target just past the limit forever (#20).
    public var rtsPose: RTSCameraPose {
        get { storedPose }
        set {
            var pose = newValue
            // Keep the camera over the island.
            let limit = scene.town.grid.radius * 1.2
            let flat = SIMD2<Float>(pose.target.x, pose.target.z)
            if simd_length(flat) > limit {
                let clamped = simd_normalize(flat) * limit
                pose.target = [clamped.x, pose.target.y, clamped.y]
            }
            storedPose = pose
        }
    }
    private var storedPose = RTSCameraPose(target: .zero, yaw: 0.6, pitch: 0.7, distance: 48)

    public var cameraMatrix: simd_float4x4? {
        get { rtsPose.cameraMatrix }
        set {
            // SceneView writes back the matrix we gave it. Converting it to a pose and back is not exact, so without
            // this check every write makes a slightly different matrix and SceneView writes again, forever.
            guard let newValue, !Self.isClose(newValue, rtsPose.cameraMatrix) else {
                return
            }
            // Read the orbit back into the pose around the same target.
            let offset = newValue.columns.3.xyz3 - rtsPose.target
            let distance = simd_length(offset)
            guard distance > 1e-4 else {
                return
            }
            rtsPose.distance = distance
            rtsPose.pitch = asin(max(-1, min(1, offset.y / distance)))
            rtsPose.yaw = atan2(offset.x, offset.z)
        }
    }
    private static func isClose(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_distance(a[$0], b[$0]) < 1e-3 }
    }

    public private(set) var hoverCell: Int?
    public private(set) var stretchSource: Int?
    public private(set) var status: String = ""
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    public let explorer: Explorer
    public let brush = Brush()
    // An undo snapshot for a whole drag.
    @ObservationIgnored private var stroke: (before: Town, changed: Bool, lastCell: Int?)?

    @ObservationIgnored private var undoStack: [Town] = []
    @ObservationIgnored private var redoStack: [Town] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    @ObservationIgnored private let persists: Bool

    public init(town: Town? = nil, persists: Bool = true) {
        self.persists = persists
        let town = town ?? Self.loadSaved() ?? Town.sample(seed: 7)
        scene = TownScene(town: town)
        explorer = Explorer(scene: scene)
        brush.model = self
    }

    // MARK: - Files

    static var saveURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "TinyTorii", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "town.json")
    }

    static func loadSaved() -> Town? {
        guard let data = try? Data(contentsOf: saveURL) else {
            return nil
        }
        return try? Town(data: data)
    }

    private func scheduleSave() {
        guard persists else {
            return
        }
        saveTask?.cancel()
        let town = scene.town
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            try? town.encoded().write(to: Self.saveURL, options: .atomic)
        }
    }

    public func export() throws -> Data {
        try scene.town.encoded()
    }

    public func load(_ data: Data) throws {
        let town = try Town(data: data)
        replace(with: town)
    }

    // MARK: - Whole-town actions

    public func newIsland() {
        replace(with: Town(gridSeed: UInt32.random(in: 1...9_999)))
        status = "A fresh island. Start with a house or a torii."
    }

    public func sampleTown() {
        replace(with: Town.sample(seed: UInt32.random(in: 1...9_999)))
        status = "A town grew by itself."
    }

    private func replace(with town: Town) {
        pushUndo()
        stretchSource = nil
        scene.replace(town: town)
        scene.setHighlight([])
        scheduleSave()
    }

    private func pushUndo() {
        undoStack.append(scene.town)
        if undoStack.count > 60 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    public func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(scene.town)
        scene.replace(town: previous)
        canUndo = !undoStack.isEmpty
        canRedo = true
        stretchSource = nil
        updateHighlight()
        scheduleSave()
    }

    public func redo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(scene.town)
        scene.replace(town: next)
        canUndo = true
        canRedo = !redoStack.isEmpty
        updateHighlight()
        scheduleSave()
    }

    // MARK: - Choosing

    public func choose(_ kind: Kind) {
        self.kind = kind
        style = min(style, kind.styles.count - 1)
        if kind.styles.count == 1 {
            style = 0
        }
        tool = .place
        stretchSource = nil
    }

    public func choose(tool: Tool) {
        self.tool = tool
        stretchSource = nil
        updateHighlight()
    }

    // MARK: - Pointer

    // True when a drag starting here should paint with the brush rather than move the camera.
    func brushClaimsDrag(at point: SIMD2<Float>, viewSize: SIMD2<Float>) -> Bool {
        guard mode == .build, let cameraMatrix else {
            return false
        }
        let viewport = SceneViewport(cameraMatrix: cameraMatrix, camera: TownCamera.camera, viewSize: viewSize, drawableSize: viewSize)
        return brush.hitTest(point, viewport: viewport)
    }

    public func hover(at point: SIMD2<Float>, viewSize: SIMD2<Float>) {
        guard mode == .build, let cameraMatrix else {
            return
        }
        let viewport = SceneViewport(cameraMatrix: cameraMatrix, camera: TownCamera.camera, viewSize: viewSize, drawableSize: viewSize)
        let cell = scene.pick(ray: viewport.ray(through: point))
        if cell != hoverCell {
            hoverCell = cell
            updateHighlight()
        }
    }

    public func endHover() {
        hoverCell = nil
        updateHighlight()
    }

    private func updateHighlight() {
        var cells: [Int] = []
        if let stretchSource {
            let group = scene.town.cells[stretchSource].item?.group
            cells = scene.town.cells.indices.filter { group != nil && scene.town.cells[$0].item?.group == group }
            if cells.isEmpty {
                cells = [stretchSource]
            }
        }
        if let hoverCell {
            cells.append(hoverCell)
        }
        scene.setHighlight(cells, stretching: stretchSource != nil)
    }

    public func tap(ray: Ray3D) {
        guard mode == .build, let cell = scene.pick(ray: ray) else {
            return
        }
        apply(at: cell)
    }

    public func apply(at cell: Int) {
        let town = scene.town
        switch tool {
        case .place:
            edit { $0.place(kind, style: style, at: cell) }
            status = "\(kind.title) placed."
        case .grow:
            edit { $0.grow(cell) }
            status = town.cells[cell].item.map { "\($0.kind.title) grew." } ?? "The ground rises."
        case .shrink:
            edit { $0.shrink(cell) }
        case .rotate:
            edit { $0.rotate(cell) }
        case .restyle:
            edit { $0.restyle(cell) }
            if let item = scene.town.cells[cell].item {
                status = "\(item.kind.title): \(item.kind.styles[item.style])"
            }
        case .remove:
            edit { $0.remove(cell) }
        case .stretch:
            if let source = stretchSource {
                if cell == source {
                    stretchSource = nil
                } else if isNextTo(cell, source: source) {
                    edit { $0.stretch(from: source, to: cell) }
                    status = "Stretched."
                } else {
                    stretchSource = cell
                }
            } else {
                stretchSource = cell
                status = "Now tap cells next to it."
            }
            updateHighlight()
        }
    }

    private func isNextTo(_ cell: Int, source: Int) -> Bool {
        let town = scene.town
        let group = town.cells[source].item?.group
        let members = group.map { group in town.cells.indices.filter { town.cells[$0].item?.group == group } } ?? [source]
        return members.contains { town.grid.neighborSet(of: $0).contains(cell) } || members.contains(source) && town.grid.neighborSet(of: source).contains(cell)
    }

    // MARK: - Strokes (drags with the brush)

    // Tools that paint along a drag. The others leave drags to camera control.
    var toolPaintsWithDrags: Bool {
        switch tool {
        case .stretch, .remove: true
        case .place: kind.paint != nil
        default: false
        }
    }

    func beginStroke(at cell: Int) {
        stroke = (scene.town, false, nil)
        continueStroke(at: cell)
    }

    func continueStroke(at cell: Int) {
        guard stroke != nil, stroke?.lastCell != cell else {
            return
        }
        let isFirst = stroke?.lastCell == nil
        stroke?.lastCell = cell
        if tool == .stretch, !isFirst {
            // Dragging only stretches; it never picks a new source.
            guard let source = stretchSource, isNextTo(cell, source: source) else {
                return
            }
            edit { $0.stretch(from: source, to: cell) }
            // Trees and props spread cell by cell; buildings grow from the whole building.
            if !(scene.town.cells[source].item?.kind.isBuilding ?? false) {
                stretchSource = cell
                updateHighlight()
            }
            return
        }
        apply(at: cell)
    }

    func endStroke() {
        guard let stroke else {
            return
        }
        if stroke.changed {
            undoStack.append(stroke.before)
            canUndo = true
        }
        self.stroke = nil
    }

    private func edit(_ change: (inout Town) -> Set<Int>) {
        let before = scene.town
        var changed = false
        scene.update { town in
            let cells = change(&town)
            changed = !cells.isEmpty
            return cells
        }
        if changed {
            if stroke == nil {
                undoStack.append(before)
            } else {
                stroke?.changed = true
            }
            redoStack.removeAll()
            canUndo = true
            canRedo = false
            scheduleSave()
        }
        updateHighlight()
    }

    // MARK: - Explore

    private func modeChanged(from old: Mode) {
        guard old != mode else {
            return
        }
        switch mode {
        case .explore:
            scene.setHighlight([])
            explorer.start()
        case .build:
            explorer.stop()
            updateHighlight()
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz3: SIMD3<Float> {
        [x, y, z]
    }
}
