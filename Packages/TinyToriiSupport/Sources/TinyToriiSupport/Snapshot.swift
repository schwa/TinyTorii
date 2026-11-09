import CoreGraphics
import Foundation
import GeometryLite3D
import ImageIO
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import UniformTypeIdentifiers

public enum TownCamera {
    public static let camera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50), depthMode: .standard(zClip: 0.05 ... 1_000)))

    public static func orbit(yaw: Float, pitch: Float, distance: Float, target: SIMD3<Float> = .zero) -> simd_float4x4 {
        let direction = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        return LookAt(position: target + direction * distance, target: target, up: [0, 1, 0]).cameraMatrix
    }

    public static func look(from position: SIMD3<Float>, yaw: Float, pitch: Float) -> simd_float4x4 {
        let forward = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
        return LookAt(position: position, target: position + forward, up: [0, 1, 0]).cameraMatrix
    }
}

@MainActor
public enum TownSnapshot {
    public enum Failure: Error {
        case imageCreationFailed
    }

    public static func renderers(time: TimeOfDay) -> [any SceneGraphMaterialRenderer] {
        [BlinnPhongMaterialRenderer(ambientLightColor: time.ambient)]
    }

    public static var shadows: SceneGraphShadows {
        SceneGraphShadows(intensity: 0.7, softness: 1, resolution: 4_096)
    }

    public static func render(scene: TownScene, cameraMatrix: simd_float4x4, width: Int, height: Int, frames: Int = 30) throws -> CGImage {
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        let shadows = Self.shadows
        let deltaTime: Float = 1 / 60
        for _ in 0..<frames {
            scene.sceneGraph.advanceActions(by: deltaTime)
            scene.sceneGraph.advanceParticles(by: deltaTime)
            scene.advance(by: deltaTime)
        }
        let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: cameraMatrix, aspectRatio: Float(width) / Float(height), renderers: renderers(time: scene.time), defaultCamera: TownCamera.camera, shadows: shadows)
        let texture = try renderer.render(element).texture
        let bytesPerRow = width * 4
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data
        else {
            throw Failure.imageCreationFailed
        }
        texture.getBytes(data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let image = context.makeImage() else {
            throw Failure.imageCreationFailed
        }
        return image
    }

    // Starts an explorer, lets it stroll, and returns where it ended up looking from.
    public static func walk(scene: TownScene, seconds: Float, flying: Bool = false) -> simd_float4x4 {
        let explorer = Explorer(scene: scene)
        explorer.start()
        explorer.isStrolling = true
        explorer.isFlying = flying
        let step: Float = 1 / 30
        var elapsed: Float = 0
        while elapsed < seconds {
            explorer.sceneView(updateAtTime: elapsed, deltaTime: step)
            elapsed += step
        }
        let matrix = explorer.cameraNode.transform
        explorer.stop()
        return matrix
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.imageCreationFailed
        }
    }
}
