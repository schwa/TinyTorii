import Foundation
import simd
import SwiftUI
import MetalSprockets
import SceneSprockets
import TinyToriiSupport

// tinytorii render [file.png] [--seed N] [--file town.json] [--empty] [--time day|morning|dusk|night]
//                  [--view overview|aerial|street|low|yaw,pitch,distance[,x,y,z]] [--size WxH]
//                  [--ops "place sakura 0 12; grow 12; stretch 12 13; remove 5"] [--highlight N]
// tinytorii save [file.json] [--seed N]
// tinytorii info [--seed N]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

@MainActor
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else {
        return nil
    }
    guard index + 1 < arguments.count else {
        fail("\(name) needs a value")
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

@MainActor
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else {
        return false
    }
    arguments.remove(at: index)
    return true
}

@MainActor
func loadTown() -> Town {
    let seed = UInt32(option("--seed") ?? "1") ?? 1
    if let path = option("--file") {
        do {
            return try Town(data: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            fail("Could not read \(path): \(error)")
        }
    }
    return flag("--empty") ? Town(gridSeed: seed) : Town.sample(seed: seed)
}

func applyOperations(_ text: String, to town: inout Town) {
    for command in text.split(separator: ";") {
        let words = command.split(separator: " ").map(String.init)
        guard let verb = words.first else {
            continue
        }
        let numbers = words.dropFirst().compactMap { Int($0) }
        switch verb {
        case "place":
            guard words.count >= 4, let kind = Kind(rawValue: words[1]), let style = Int(words[2]), let cell = Int(words[3]) else {
                fail("place KIND STYLE CELL")
            }
            town.place(kind, style: style, at: cell)
        case "grow": numbers.forEach { town.grow($0) }
        case "shrink": numbers.forEach { town.shrink($0) }
        case "remove": numbers.forEach { town.remove($0) }
        case "rotate": numbers.forEach { town.rotate($0) }
        case "restyle": numbers.forEach { town.restyle($0) }
        case "stretch":
            guard numbers.count >= 2 else {
                fail("stretch FROM TO...")
            }
            for target in numbers.dropFirst() {
                town.stretch(from: numbers[0], to: target)
            }
        default:
            fail("unknown operation \(verb)")
        }
    }
}

@MainActor
func cameraMatrix(view: String, scene: TownScene) -> simd_float4x4 {
    let town = scene.town
    let radius = town.grid.radius
    switch view {
    case "overview":
        return TownCamera.orbit(yaw: 0.6, pitch: 0.62, distance: radius * 2.1, target: [0, 0, 0])
    case "aerial":
        return TownCamera.orbit(yaw: 0.2, pitch: 1.35, distance: radius * 2.6)
    case "low":
        return TownCamera.orbit(yaw: 2.4, pitch: 0.28, distance: radius * 1.5, target: [0, 1, 0])
    case "street":
        // From a path cell near the middle, looking at the tallest thing.
        let cells = town.grid.cells.indices
        let start = cells.filter { town.cells[$0].ground == .path && town.cells[$0].item == nil }.min { simd_length(town.grid.cells[$0].center) < simd_length(town.grid.cells[$1].center) } ?? 0
        let tallest = cells.max { scene.top(of: $0) < scene.top(of: $1) } ?? 0
        let position = town.grid.cells[start].center.lifted3(town.standingHeight(start) + 0.55)
        let target = town.grid.cells[tallest].center
        let delta = target - position.xz2
        return TownCamera.look(from: position, yaw: atan2(delta.x, -delta.y), pitch: 0.12)
    default:
        let numbers = view.split(separator: ",").compactMap { Float($0) }
        guard numbers.count == 3 || numbers.count == 6 else {
            fail("--view must be overview, aerial, low, street or yaw,pitch,distance[,x,y,z]")
        }
        let target: SIMD3<Float> = numbers.count == 6 ? [numbers[3], numbers[4], numbers[5]] : .zero
        return TownCamera.orbit(yaw: numbers[0], pitch: numbers[1], distance: numbers[2], target: target)
    }
}

extension SIMD2 where Scalar == Float {
    func lifted3(_ y: Float) -> SIMD3<Float> {
        [x, y, self.y]
    }
}

extension SIMD3 where Scalar == Float {
    var xz2: SIMD2<Float> {
        [x, z]
    }
}

switch arguments.first {
case "render":
    arguments.removeFirst()
    let size = (option("--size") ?? "1600x1000").split(separator: "x").compactMap { Int($0) }
    guard size.count == 2 else {
        fail("--size must look like 1600x1000")
    }
    let timeName = (option("--time") ?? "day").lowercased()
    let time = TimeOfDay.allCases.first { $0.rawValue.lowercased() == timeName } ?? .day
    let view = option("--view") ?? "overview"
    let operations = option("--ops")
    let highlight = option("--highlight").flatMap { Int($0) }
    let walkSeconds = option("--walk").flatMap { Float($0) }
    let flySeconds = option("--fly").flatMap { Float($0) }
    var town = loadTown()
    if let operations {
        applyOperations(operations, to: &town)
    }
    let url = URL(fileURLWithPath: arguments.first ?? "tinytorii.png")
    let start = Date()
    do {
        try MainActor.assumeIsolated {
            let scene = TownScene(town: town, time: time)
            if let highlight {
                scene.setHighlight([highlight])
            }
            let built = Date()
            var camera = cameraMatrix(view: view, scene: scene)
            if let walkSeconds {
                camera = TownSnapshot.walk(scene: scene, seconds: walkSeconds)
            }
            if let flySeconds {
                camera = TownSnapshot.walk(scene: scene, seconds: flySeconds, flying: true)
            }
            let image = try TownSnapshot.render(scene: scene, cameraMatrix: camera, width: size[0], height: size[1])
            try TownSnapshot.writePNG(image, to: url)
            FileHandle.standardError.write(Data(String(format: "built in %.2fs, rendered in %.2fs\n", built.timeIntervalSince(start), Date().timeIntervalSince(built)).utf8))
        }
        print(url.path)
    } catch {
        fail("\(error)")
    }
case "save":
    arguments.removeFirst()
    let town = loadTown()
    let url = URL(fileURLWithPath: arguments.first ?? "town.json")
    do {
        try town.encoded().write(to: url)
        print(url.path)
    } catch {
        fail("\(error)")
    }
case "gallery":
    // One close-up per kind and style, on an empty island: a single cell, then stretched over three cells and grown.
    arguments.removeFirst()
    let kinds = option("--kinds").map { $0.split(separator: ",").compactMap { Kind(rawValue: String($0)) } } ?? Kind.allCases.filter { $0.paint == nil }
    let timeName = (option("--time") ?? "day").lowercased()
    let time = TimeOfDay.allCases.first { $0.rawValue.lowercased() == timeName } ?? .day
    let folder = URL(fileURLWithPath: arguments.first ?? "gallery", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        let empty = Town(gridSeed: 1)
        let center = empty.grid.cells.indices.min { simd_length(empty.grid.cells[$0].center) < simd_length(empty.grid.cells[$1].center) }!
        let neighbors = empty.grid.neighborSet(of: center)
        let scene = TownScene(town: empty, time: time)
        for kind in kinds {
            for style in kind.styles.indices {
                var town = empty
                town.place(kind, style: style, at: center, rotation: atan2(cos(Float(0.7)), sin(Float(0.7))) + .pi / 2)
                var focus = town.grid.cells[center].center
                if kind.isBuilding || kind.category == .trees || kind == .bambooFence {
                    town.stretch(from: center, to: neighbors[0])
                    town.stretch(from: center, to: neighbors[1])
                    town.place(kind, style: style, at: neighbors[3])
                    for _ in 0..<kind.maxLevel {
                        town.grow(neighbors[3])
                    }
                    focus = (town.grid.cells[center].center + town.grid.cells[neighbors[3]].center) / 2
                }
                scene.replace(town: town)
                let height: Float = kind == .castle || kind == .pagoda ? 2.5 : (kind.isBuilding || kind.category == .trees ? 1 : 0.4)
                let distance: Float = kind.isBuilding ? 8 : (kind.category == .trees ? 6 : 3.2)
                let camera = TownCamera.orbit(yaw: 0.7, pitch: 0.42, distance: distance, target: [focus.x, height, focus.y])
                let name = "\(kind.rawValue)-\(style)"
                do {
                    let image = try TownSnapshot.render(scene: scene, cameraMatrix: camera, width: 640, height: 480, frames: 0)
                    try TownSnapshot.writePNG(image, to: folder.appending(path: "\(name).png"))
                    print(name)
                } catch {
                    fail("\(error)")
                }
            }
        }
    }
case "thumbnails":
    // Small pictures of every kind for the palette, saved as the package's resources.
    arguments.removeFirst()
    let folder = URL(fileURLWithPath: arguments.first ?? "Thumbnails", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        let empty = Town(gridSeed: 1)
        let center = empty.grid.cells.indices.min { simd_length(empty.grid.cells[$0].center) < simd_length(empty.grid.cells[$1].center) }!
        let scene = TownScene(town: empty, time: .day)
        let yaw: Float = 0.7
        for kind in Kind.allCases {
            var town = empty
            town.place(kind, style: 0, at: center, rotation: atan2(cos(yaw), sin(yaw)) + .pi / 2)
            if kind.paint != nil {
                for neighbor in town.grid.neighborSet(of: center) {
                    town.place(kind, style: 0, at: neighbor)
                }
            }
            scene.replace(town: town)
            let focus = town.grid.cells[center].center
            let top = max(scene.top(of: center), 0.3)
            let distance = kind.paint != nil ? 6 : (kind.category == .animals ? (kind == .crane ? 1.9 : 1.3) : max(2.2, top * 1.3 + 1.1))
            let camera = TownCamera.orbit(yaw: yaw, pitch: kind.paint != nil ? 0.9 : 0.38, distance: distance, target: [focus.x, top * 0.5, focus.y])
            do {
                let image = try TownSnapshot.render(scene: scene, cameraMatrix: camera, width: 192, height: 144, frames: 0)
                try TownSnapshot.writePNG(image, to: folder.appending(path: "\(kind.rawValue).png"))
                print(kind.rawValue)
            } catch {
                fail("\(error)")
            }
        }
    }
case "icon":
    // A great torii at dusk with cherry trees, for the app icon.
    arguments.removeFirst()
    let url = URL(fileURLWithPath: arguments.first ?? "icon.png")
    MainActor.assumeIsolated {
        var town = Town(gridSeed: 1)
        let center = town.grid.cells.indices.min { simd_length(town.grid.cells[$0].center) < simd_length(town.grid.cells[$1].center) }!
        town.place(.greatTorii, style: 0, at: center, rotation: 0)
        town.place(.paintGravel, style: 0, at: center)
        let focus = town.grid.cells[center].center
        for neighbor in town.grid.neighborSet(of: center) {
            let offset = town.grid.cells[neighbor].center - focus
            if offset.y < -0.5 {
                town.place(.sakura, style: 0, at: neighbor)
                town.grow(neighbor)
            } else if abs(offset.x) > 1 {
                town.place(.stoneLantern, style: 0, at: neighbor)
            }
        }
        let scene = TownScene(town: town, time: .dusk)
        let camera = TownCamera.look(from: [focus.x, 1.2, focus.y + 6.5], yaw: 0, pitch: 0.06)
        do {
            let image = try TownSnapshot.render(scene: scene, cameraMatrix: camera, width: 1_024, height: 1_024, frames: 0)
            try TownSnapshot.writePNG(image, to: url)
            print(url.path)
        } catch {
            fail("\(error)")
        }
    }
case "ui":
    // The SwiftUI overlay, drawn with ImageRenderer (the Metal view itself stays blank), to check layout.
    arguments.removeFirst()
    let url = URL(fileURLWithPath: arguments.first ?? "ui.png")
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: TownView().frame(width: 1_400, height: 900).background(Color.gray))
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            fail("no image")
        }
        try? TownSnapshot.writePNG(image, to: url)
        print(url.path)
    }
case "bench":
    // Renders frames back to back, advancing the scene like the app does, and prints the mean frame time.
    arguments.removeFirst()
    let frames = option("--frames").flatMap { Int($0) } ?? 120
    let timeName = (option("--time") ?? "day").lowercased()
    let time = TimeOfDay.allCases.first { $0.rawValue.lowercased() == timeName } ?? .day
    let still = flag("--still")
    let view = option("--view") ?? "overview"
    // Diagnostics: switch parts off to see what they cost.
    let noShadows = flag("--no-shadows")
    let noFog = flag("--no-fog")
    let town = loadTown()
    MainActor.assumeIsolated {
        let scene = TownScene(town: town, time: time)
        let renderer = try! OffscreenRenderer(size: CGSize(width: 1_600, height: 1_000), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        let shadows: SceneGraphShadows? = noShadows ? nil : TownSnapshot.shadows
        if noFog {
            scene.sceneGraph.fog = nil
        }
        let camera = cameraMatrix(view: view, scene: scene)
        var times: [Double] = []
        var gpuTimes: [Double] = []
        let renderers = TownSnapshot.renderers(time: time)
        for frame in 0..<frames {
            let start = ContinuousClock.now
            if !still {
                scene.advance(by: 1 / 60)
            }
            scene.sceneGraph.advanceActions(by: 1 / 60)
            scene.sceneGraph.advanceParticles(by: 1 / 60)
            let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: camera, aspectRatio: 1.6, renderers: renderers, defaultCamera: TownCamera.camera, shadows: shadows)
            let rendering = try! renderer.render(element)
            if frame >= 10, let gpu = rendering.gpuTime { gpuTimes.append(gpu * 1_000) }
            let elapsed = ContinuousClock.now - start
            if frame >= 10 {
                times.append(Double(elapsed.components.attoseconds) * 1e-15 + Double(elapsed.components.seconds) * 1_000)
            }
        }
        times.sort()
        gpuTimes.sort()
        let statistics = scene.sceneGraph.statistics
        print(String(format: "mean %.2f ms  median %.2f ms  gpu %.2f ms  meshes %d  triangles %d  lights %d", times.reduce(0, +) / Double(times.count), times[times.count / 2], gpuTimes.isEmpty ? 0 : gpuTimes[gpuTimes.count / 2], statistics.meshCount, statistics.triangleCount, statistics.lightCount))
    }
case "info":
    arguments.removeFirst()
    let town = loadTown()
    let items = town.cells.compactMap(\.item)
    print("cells \(town.grid.cells.count)  vertices \(town.grid.vertices.count)  items \(items.count)")
    var counts: [Kind: Int] = [:]
    for item in items {
        counts[item.kind, default: 0] += 1
    }
    for (kind, count) in counts.sorted(by: { $0.value > $1.value }) {
        print("  \(kind.rawValue): \(count)")
    }
default:
    fail("usage: tinytorii render|save|info ...")
}
