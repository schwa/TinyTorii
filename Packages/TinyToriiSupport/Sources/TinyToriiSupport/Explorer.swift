import Foundation
import GeometryLite3D
import Interaction3D
import SceneSprockets
import simd

// Walks a person-height camera through the town, or strolls or flies by itself. Input comes from Interaction3D:
// WASDController (W A S D move, arrows look, Shift hurries, mouse looks while captured) and
// GameControllerMovementController (sticks); plus an on-screen joystick and drag-to-look from the view.
@MainActor
public final class Explorer: SceneViewDelegate {
    public let cameraNode: SceneGraph.Node
    public var isStrolling = false
    // A slow bird's-eye circle around the island.
    public var isFlying = false
    private var flightAngle: Float = 0
    // Joystick, -1...1 each axis: x strafes, y walks.
    public var stick: SIMD2<Float> = .zero
    private var keyboard: WASDController?
    private var gamepad: GameControllerMovementController?
    private var inputTasks: [Task<Void, Never>] = []
    private var keyMove: SIMD2<Float> = .zero
    private var keyLook: SIMD2<Float> = .zero
    private var isFast = false
    private var padMove: SIMD2<Float> = .zero
    private var padLook: SIMD2<Float> = .zero
    static let mouseSensitivity: Float = 0.0025
    private let scene: TownScene
    private var position: SIMD2<Float> = .zero
    private var height: Float = 0.6
    public private(set) var yaw: Float = 0
    public var pitch: Float = 0.05
    private var bobPhase: Float = 0
    private var strollTarget: SIMD2<Float>?
    private var strollTargetCell: Int?
    private var lastProgress: SIMD2<Float> = .zero
    private var stuckTime: Float = 0
    private var recentCells: [Int] = []
    private var lookOffsetYaw: Float = 0

    static let eyeHeight: Float = 0.55

    init(scene: TownScene) {
        self.scene = scene
        cameraNode = SceneGraph.Node(label: "Walker", content: .camera(TownCamera.camera))
    }

    func start() {
        let town = scene.town
        let cells = town.grid.cells.indices
        let walkable = cells.filter { scene.isWalkable(town.grid.cells[$0].center, from: town.standingHeight($0)) }
        let preferred = walkable.filter { town.cells[$0].ground == .path || town.cells[$0].ground == .gravel }
        let start = (preferred.isEmpty ? walkable : preferred).min { simd_length(town.grid.cells[$0].center) < simd_length(town.grid.cells[$1].center) } ?? 0
        position = town.grid.cells[start].center
        height = town.standingHeight(start) + Self.eyeHeight
        // Face the tallest thing.
        let tallest = cells.max { scene.top(of: $0) < scene.top(of: $1) } ?? start
        let delta = town.grid.cells[tallest].center - position
        yaw = atan2(delta.x, -delta.y)
        pitch = 0.08
        recentCells = []
        strollTarget = nil
        scene.root.addChild(cameraNode)
        updateCamera()
        startInput()
    }

    func stop() {
        isFlying = false
        cameraNode.removeFromParent()
        stick = .zero
        isStrolling = false
        stopInput()
    }

    // MARK: - Input

    // GCKeyboard is global, so the view turns this off when it loses focus.
    public var isKeyboardEnabled = true {
        didSet { keyboard?.isKeyboardEnabled = isKeyboardEnabled }
    }

    public var isMouseCaptured: Bool {
        keyboard?.isMouseCaptured ?? false
    }

    public func toggleMouseCapture() {
        keyboard?.toggleMouseCapture()
    }

    public func releaseMouse() {
        keyboard?.releaseMouse()
    }

    private func startInput() {
        stopInput()
        let keyboard = WASDController()
        keyboard.isKeyboardEnabled = isKeyboardEnabled
        let gamepad = GameControllerMovementController()
        self.keyboard = keyboard
        self.gamepad = gamepad
        inputTasks = [keyboard.events, gamepad.events].map { events in
            Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
            }
        }
    }

    private func stopInput() {
        inputTasks.forEach { $0.cancel() }
        inputTasks = []
        keyboard?.releaseMouse()
        keyboard = nil
        gamepad = nil
        keyMove = .zero
        keyLook = .zero
        padMove = .zero
        padLook = .zero
        isFast = false
    }

    private func handle(_ event: NavigationEvent) {
        switch event {
        case let .keyboardState(move, look, _, fast):
            keyMove = move
            keyLook = look
            isFast = fast
        case let .look(deltaX, deltaY, source):
            // The mouse only looks while captured; otherwise it is for clicking and dragging.
            if source == .controller || isMouseCaptured {
                look(by: [deltaX * Self.mouseSensitivity, deltaY * Self.mouseSensitivity])
            }
        case let .controllerState(move, look, _):
            padMove = move
            padLook = look
        case let .axes(forward, sideways, source) where source == .controller:
            padMove = [sideways, forward]
        default:
            break
        }
        if simd_length(keyMove) + simd_length(padMove) > 0.1 {
            isStrolling = false
            isFlying = false
        }
    }

    public func look(by delta: SIMD2<Float>) {
        yaw += delta.x
        pitch = max(-1.2, min(1.2, pitch + delta.y))
    }

    public func sceneView(updateAtTime _: Float, deltaTime: Float) {
        scene.advance(by: deltaTime)
        guard cameraNode.parent != nil else {
            return
        }
        let deltaTime = min(deltaTime, 0.05)
        let turn = keyLook + padLook
        if isFlying {
            flightAngle += turn.x * deltaTime * 0.4
            flightAngle += deltaTime * 0.05
            let radius = scene.town.grid.radius * 0.95
            let eye = SIMD3<Float>(sin(flightAngle) * radius, 9 + sin(flightAngle * 3) * 1.5, cos(flightAngle) * radius)
            let target = SIMD3<Float>(sin(flightAngle + 0.9) * radius * 0.25, 1, cos(flightAngle + 0.9) * radius * 0.25)
            cameraNode.transform = LookAt(position: eye, target: target, up: [0, 1, 0]).cameraMatrix
            return
        }
        yaw += turn.x * 1.8 * deltaTime
        pitch = max(-1.2, min(1.2, pitch + turn.y * 1.2 * deltaTime))
        var move = keyMove + padMove + stick
        var speed: Float = isFast ? 3.6 : 1.7
        if isStrolling {
            move = stroll(deltaTime: deltaTime)
            speed = 1.1
            // Stuck for a while: turn around and forget where we've been.
            stuckTime += deltaTime
            if simd_distance(position, lastProgress) > 0.5 {
                lastProgress = position
                stuckTime = 0
            } else if stuckTime > 2.5 {
                yaw += .pi
                recentCells.removeAll()
                strollTarget = nil
                stuckTime = 0
            }
        }
        if simd_length(move) > 0.01 {
            if simd_length(move) > 1 {
                move = simd_normalize(move)
            }
            let forward = SIMD2<Float>(sin(yaw), -cos(yaw))
            let right = SIMD2<Float>(cos(yaw), sin(yaw))
            let step = (forward * move.y + right * move.x) * speed * deltaTime
            walk(step)
            bobPhase += simd_length(step) * 5.5
        }
        let ground = scene.walkHeight(at: position).map { $0 + Self.eyeHeight + bridgeLift() } ?? height
        height += (ground - height) * min(1, deltaTime * 8)
        updateCamera()
    }

    private func bridgeLift() -> Float {
        guard let cell = scene.town.grid.cell(at: position), scene.town.cells[cell].item?.kind == .bridge else {
            return 0
        }
        let distance = simd_distance(position, scene.town.grid.cells[cell].center)
        return 0.42 * max(0, 1 - distance / 0.95)
    }

    // Moves, sliding along walls when the direct step is blocked.
    private func walk(_ step: SIMD2<Float>) {
        let current = scene.walkHeight(at: position) ?? 0
        for candidate in [step, SIMD2(step.x, 0), SIMD2(0, step.y)] {
            let next = position + candidate
            // Keep a little distance from blocked cells.
            let probe = next + simd_normalize(candidate + SIMD2(1e-6, 0)) * 0.32
            if scene.isWalkable(next, from: current), scene.isWalkable(probe, from: current) {
                position = next
                return
            }
        }
        if isStrolling {
            // Blocked: don't try that cell again soon.
            if let strollTargetCell {
                recentCells.append(strollTargetCell)
            }
            strollTarget = nil
            strollTargetCell = nil
        }
    }

    // Picks a walkable neighbor, walks to its center, and turns smoothly toward it.
    private func stroll(deltaTime: Float) -> SIMD2<Float> {
        let town = scene.town
        if strollTarget == nil || simd_distance(strollTarget!, position) < 0.35 {
            guard let cell = town.grid.cell(at: position) else {
                return .zero
            }
            recentCells.append(cell)
            if recentCells.count > 12 {
                recentCells.removeFirst()
            }
            let heading = SIMD2<Float>(sin(yaw), -cos(yaw))
            let current = town.standingHeight(cell)
            let options = town.grid.neighborSet(of: cell).filter { scene.isWalkable(town.grid.cells[$0].center, from: current) }
            let scored = options.map { neighbor -> (Int, Float) in
                let direction = simd_normalize(town.grid.cells[neighbor].center - position)
                var score = simd_dot(direction, heading) + Float.random(in: 0...0.9)
                if town.cells[neighbor].ground == .path || town.cells[neighbor].ground == .gravel { score += 0.6 }
                if recentCells.contains(neighbor) { score -= 1.5 }
                return (neighbor, score)
            }
            guard let best = scored.max(by: { $0.1 < $1.1 }) else {
                yaw += .pi * deltaTime
                return .zero
            }
            strollTarget = town.grid.cells[best.0].center
            strollTargetCell = best.0
        }
        guard let target = strollTarget else {
            return .zero
        }
        let delta = target - position
        let desired = atan2(delta.x, -delta.y)
        var difference = desired - yaw
        while difference > .pi { difference -= 2 * .pi }
        while difference < -.pi { difference += 2 * .pi }
        yaw += difference * min(1, deltaTime * 2.5)
        pitch += (0.04 - pitch) * min(1, deltaTime)
        return [0, abs(difference) < 1.2 ? 1 : 0.2]
    }

    private func updateCamera() {
        let bob = sin(bobPhase) * 0.018
        cameraNode.transform = TownCamera.look(from: position.lifted(height + bob), yaw: yaw, pitch: pitch)
    }
}
