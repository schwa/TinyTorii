import MetalSprockets
import SceneSprockets
import simd
#if canImport(AppKit)
import AppKit
#endif

// Takes drags away from camera control when the tool paints along a drag (stretch, remove, ground paint), so a drag
// across the island stretches a building or paints a path. Hold Option to orbit instead.
@MainActor
public final class Brush: SceneViewManipulator {
    weak var model: TownModel?

    public func overlay(viewport _: SceneViewport) throws -> AnyElement? {
        nil
    }

    public func hitTest(_ point: SIMD2<Float>, viewport: SceneViewport) -> Bool {
        guard let model, model.mode == .build, model.toolPaintsWithDrags else {
            return false
        }
        #if canImport(AppKit)
        if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.command) {
            return false
        }
        #endif
        return model.scene.pick(ray: viewport.ray(through: point)) != nil
    }

    public func beginDrag(at point: SIMD2<Float>, viewport: SceneViewport) {
        guard let model, let cell = model.scene.pick(ray: viewport.ray(through: point)) else {
            return
        }
        model.beginStroke(at: cell)
    }

    public func drag(to point: SIMD2<Float>, viewport: SceneViewport) {
        guard let model, let cell = model.scene.pick(ray: viewport.ray(through: point)) else {
            return
        }
        model.continueStroke(at: cell)
    }

    public func endDrag() {
        model?.endStroke()
    }
}
