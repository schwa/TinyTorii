import Foundation
import GeometryLite3D
import Interaction3D
import SceneSprockets
import simd

// Walks a person-height camera through the town, or strolls or flies by itself. Walking by hand uses Interaction3D's
// FPVNavigator in walk mode (the view adds `.fpvMovement(navigator)` for keys, mouse and game controllers), with
// hooks for the town's ground and obstacles, plus an on-screen joystick and drag-to-look. Strolling and flying move
// the camera themselves.
@MainActor
public final class Explorer: SceneViewDelegate {
    public let cameraNode: SceneGraph.Node
    public var isStrolling = false
    // A slow bird's-eye circle around the island.
    public var isFlying = false {
        didSet {
            if oldValue, !isFlying, cameraNode.parent != nil {
                land()
            }
        }
    }
    private var flightAngle: Float = 0
    // Joystick, -1...1 each axis: x strafes, y walks.
    public var stick: SIMD2<Float> = .zero {
        didSet { navigator.moveInput = stick }
    }
    public let navigator = FPVNavigator()
    // Set when strolling, flying or start() moved the camera, so the navigator's pose must be reset from it.
    private var needsFPVPose = true
    private let scene: TownScene
    private var position: SIMD2<Float> = .zero
    private var height: Float = 1.6
    public private(set) var yaw: Float = 0
    public var pitch: Float = 0.05
    private var bobPhase: Float = 0
    private var strollTarget: SIMD2<Float>?
    private var strollTargetCell: Int?
    private var lastProgress: SIMD2<Float> = .zero
    private var stuckTime: Float = 0
    private var recentCells: [Int] = []
    private var lookOffsetYaw: Float = 0

    // Meters: a person's eyes.
    static let eyeHeight: Float = 1.6

    init(scene: TownScene) {
        self.scene = scene
        cameraNode = SceneGraph.Node(label: "Walker", content: .camera(TownCamera.camera))
        navigator.settings = FPVMovementSettings(
            speed: 5.95,
            fastSpeedMultiplier: 3.6 / 1.7,
            mouseSensitivity: 0.0025,
            keyboardTurnSpeed: 1.8,
            walk: FPVWalkSettings(gravity: 9.8, eyeHeight: Self.eyeHeight, groundFollowRate: 8)
        )
        navigator.hooks = Self.hooks(scene: scene)
        // The mouse looks only while captured; otherwise it is for clicking and dragging.
        navigator.isMouseLookEnabled = false
    }

    // Captures the scene, not self: the navigator is stored in self.
    private static func hooks(scene: TownScene) -> FPVMovementHooks {
        FPVMovementHooks(
            groundHeight: { eye in
                let point = SIMD2<Float>(eye.x, eye.z)
                return scene.walkHeight(at: point).map { $0 + bridgeLift(at: point, scene: scene) }
            },
            canMove: { from, to in
                let start = SIMD2<Float>(from.x, from.z)
                let next = SIMD2<Float>(to.x, to.z)
                let step = next - start
                guard simd_length(step) > 0 else {
                    return true
                }
                let current = scene.walkHeight(at: start) ?? 0
                // Keep a little distance from blocked cells.
                let probe = next + simd_normalize(step) * 1.12
                return scene.isWalkable(next, from: current) && scene.isWalkable(probe, from: current)
            },
            adjustCamera: { matrix, state in
                guard state.isOnGround else {
                    return matrix
                }
                var matrix = matrix
                matrix.columns.3.y += sin(state.distanceWalked * 1.571) * 0.063
                return matrix
            }
        )
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
        navigator.reset()
        needsFPVPose = true
    }

    // The flight path runs out over the sea, where walking would fall forever (#23): come down on the nearest
    // walkable cell, facing the way the flight looked.
    private func land() {
        let transform = cameraNode.transform
        let point = SIMD2<Float>(transform.columns.3.x, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let town = scene.town
        let nearest = town.grid.cells.indices
            .filter { scene.isWalkable(town.grid.cells[$0].center, from: town.standingHeight($0)) }
            .min { simd_distance(town.grid.cells[$0].center, point) < simd_distance(town.grid.cells[$1].center, point) }
        if scene.walkHeight(at: point) != nil {
            position = point
        } else if let nearest {
            position = town.grid.cells[nearest].center
        } else {
            return
        }
        height = (scene.walkHeight(at: position) ?? 0) + Self.eyeHeight + bridgeLift()
        yaw = atan2(forward.x, -forward.z)
        pitch = 0.08
        updateCamera()
        navigator.reset()
        needsFPVPose = true
    }

    func stop() {
        isFlying = false
        cameraNode.removeFromParent()
        stick = .zero
        isStrolling = false
        releaseMouse()
    }

    // MARK: - Input

    public var isMouseCaptured: Bool {
        navigator.isMouseCaptured
    }

    public func toggleMouseCapture() {
        if isMouseCaptured {
            releaseMouse()
        } else {
            navigator.isMouseLookEnabled = true
            navigator.captureMouse()
        }
    }

    public func releaseMouse() {
        // Also releases the capture.
        navigator.isMouseLookEnabled = false
    }

    // Radians; positive yaw turns right, positive pitch looks up.
    public func look(by delta: SIMD2<Float>) {
        yaw += delta.x
        pitch = max(-1.2, min(1.2, pitch + delta.y))
        navigator.look(yaw: delta.x, pitch: delta.y)
    }

    public func sceneView(updateAtTime _: Float, deltaTime: Float) {
        scene.advance(by: deltaTime)
        guard cameraNode.parent != nil else {
            return
        }
        let deltaTime = min(deltaTime, 0.05)
        if navigator.hasMovementInput {
            isStrolling = false
            isFlying = false
        }
        if isFlying {
            flightAngle += deltaTime * 0.05
            let radius = scene.town.grid.radius * 0.95
            let eye = SIMD3<Float>(sin(flightAngle) * radius, 31.5 + sin(flightAngle * 3) * 5.25, cos(flightAngle) * radius)
            let target = SIMD3<Float>(sin(flightAngle + 0.9) * radius * 0.25, 3.5, cos(flightAngle + 0.9) * radius * 0.25)
            cameraNode.transform = LookAt(position: eye, target: target, up: [0, 1, 0]).cameraMatrix
            needsFPVPose = true
            return
        }
        if !isStrolling {
            walkByHand(deltaTime: deltaTime)
            return
        }
        needsFPVPose = true
        var move = stroll(deltaTime: deltaTime)
        let speed: Float = 3.85
        // Stuck for a while: turn around and forget where we've been.
        stuckTime += deltaTime
        if simd_distance(position, lastProgress) > 1.75 {
            lastProgress = position
            stuckTime = 0
        } else if stuckTime > 2.5 {
            yaw += .pi
            recentCells.removeAll()
            strollTarget = nil
            stuckTime = 0
        }
        if simd_length(move) > 0.01 {
            if simd_length(move) > 1 {
                move = simd_normalize(move)
            }
            let forward = SIMD2<Float>(sin(yaw), -cos(yaw))
            let right = SIMD2<Float>(cos(yaw), sin(yaw))
            let step = (forward * move.y + right * move.x) * speed * deltaTime
            walk(step)
            bobPhase += simd_length(step) * 1.571
        }
        let ground = scene.walkHeight(at: position).map { $0 + Self.eyeHeight + bridgeLift() } ?? height
        height += (ground - height) * min(1, deltaTime * 8)
        updateCamera()
    }

    private func walkByHand(deltaTime: Float) {
        if needsFPVPose {
            navigator.setPose(cameraNode.transform)
            needsFPVPose = false
        }
        navigator.update(deltaTime: deltaTime)
        let transform = navigator.transform
        cameraNode.transform = transform
        // Keep our pose in step, so strolling and flying start from here.
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        position = [transform.columns.3.x, transform.columns.3.z]
        height = transform.columns.3.y
        yaw = atan2(forward.x, -forward.z)
        pitch = asin(max(-1, min(1, forward.y)))
    }

    private func bridgeLift() -> Float {
        Self.bridgeLift(at: position, scene: scene)
    }

    private static func bridgeLift(at point: SIMD2<Float>, scene: TownScene) -> Float {
        guard let cell = scene.town.grid.cell(at: point), scene.town.cells[cell].item?.kind == .bridge else {
            return 0
        }
        let distance = simd_distance(point, scene.town.grid.cells[cell].center)
        return 1.47 * max(0, 1 - distance / 3.325)
    }

    // Moves, sliding along walls when the direct step is blocked.
    private func walk(_ step: SIMD2<Float>) {
        let current = scene.walkHeight(at: position) ?? 0
        for candidate in [step, SIMD2(step.x, 0), SIMD2(0, step.y)] {
            let next = position + candidate
            // Keep a little distance from blocked cells.
            let probe = next + simd_normalize(candidate + SIMD2(1e-6, 0)) * 1.12
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
        if strollTarget == nil || simd_distance(strollTarget!, position) < 1.225 {
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
        let bob = sin(bobPhase) * 0.063
        cameraNode.transform = TownCamera.look(from: position.lifted(height + bob), yaw: yaw, pitch: pitch)
    }
}
