import ImageIO
import Interaction3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI
import UniformTypeIdentifiers

public struct TownView: View {
    @State private var model = TownModel()
    @State private var shadows = TownSnapshot.shadows
    @State private var viewSize: CGSize = .zero
    @State private var lastLook: CGSize = .zero
    @State private var isExporting = false
    @State private var isImporting = false
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            sceneView
                .ignoresSafeArea()
            if model.mode == .build {
                buildOverlay
            } else {
                exploreOverlay
            }
        }
        .fontDesign(.serif)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onChange(of: model.mode) { isFocused = true }
        .onChange(of: isFocused) { model.explorer.isKeyboardEnabled = isFocused }
        .onKeyPress(phases: [.down, .up]) { press in
            handleKey(press)
        }
        .fileExporter(isPresented: $isExporting, document: TownDocument(data: (try? model.export()) ?? Data()), contentType: .json, defaultFilename: "Town") { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                if let data = try? Data(contentsOf: url) {
                    try? model.load(data)
                }
            }
        }
    }

    private var sceneView: some View {
        SceneView(
            sceneGraph: model.scene.sceneGraph,
            pointOfView: model.mode == .explore ? model.explorer.cameraNode : nil,
            options: model.mode == .build ? [.allowsCameraControl] : [],
            renderers: TownSnapshot.renderers(time: model.time),
            delegate: model.explorer,
            shadows: shadows,
            cameraMatrix: model.mode == .build ? $model.cameraMatrix : nil,
            cameraTarget: model.rtsPose.target,
            defaultCamera: TownCamera.camera,
            manipulator: model.mode == .build ? model.brush : nil,
            onTapAt: { point, viewport, _ in
                model.tap(ray: viewport.ray(through: point))
            },
            closuresID: "town"
        )
        .id(model.mode)
        .modifier(BuildCameraKeys(isEnabled: model.mode == .build, pose: $model.rtsPose))
        .sceneCameraControl(SceneCameraControl(distanceRange: 6...110, pitchRange: 0.08...1.5))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                model.hover(at: [Float(location.x), Float(location.y)], viewSize: [Float(viewSize.width), Float(viewSize.height)])
            case .ended:
                model.endHover()
            }
        }
        .simultaneousGesture(lookGesture, including: model.mode == .explore ? .all : .subviews)
    }

    private var lookGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - lastLook.width, height: value.translation.height - lastLook.height)
                lastLook = value.translation
                model.explorer.look(by: [Float(delta.width) * 0.005, Float(-delta.height) * 0.005])
            }
            .onEnded { _ in lastLook = .zero }
    }

    // MARK: - Keys

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if model.mode == .build {
            guard press.phase == .down else {
                return .ignored
            }
            switch press.characters.lowercased() {
            case "x":
                model.mode = .explore
            case "z" where press.modifiers.contains(.command):
                if press.modifiers.contains(.shift) { model.redo() } else { model.undo() }
            case "1": model.choose(tool: .place)
            case "2": model.choose(tool: .grow)
            case "3": model.choose(tool: .shrink)
            case "4": model.choose(tool: .stretch)
            case "5": model.choose(tool: .rotate)
            case "6": model.choose(tool: .restyle)
            case "7": model.choose(tool: .remove)
            case "t":
                let all = TimeOfDay.allCases
                model.time = all[(all.firstIndex(of: model.time)! + 1) % all.count]
            default:
                return .ignored
            }
            return .handled
        }
        // Interaction3D's WASDController reads movement keys straight from the keyboard; claim them so they don't beep.
        if [.upArrow, .downArrow, .leftArrow, .rightArrow].contains(press.key) || "wasdqe".contains(press.characters.lowercased()) && !press.characters.isEmpty {
            return .handled
        }
        guard press.phase == .down else {
            return .ignored
        }
        switch press.key {
        case .space:
            model.explorer.isFlying = false
            model.explorer.isStrolling.toggle()
        case .escape:
            if model.explorer.isMouseCaptured {
                model.explorer.releaseMouse()
            } else {
                model.mode = .build
            }
        default:
            if press.characters.lowercased() == "m" {
                model.explorer.toggleMouseCapture()
            } else if press.characters.lowercased() == "f" {
                model.explorer.isFlying.toggle()
            } else if press.characters.lowercased() == "t" {
                let all = TimeOfDay.allCases
                model.time = all[(all.firstIndex(of: model.time)! + 1) % all.count]
            } else {
                return .ignored
            }
        }
        return .handled
    }

    // MARK: - Build overlay

    private var buildOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            HStack(alignment: .bottom) {
                toolColumn
                Spacer()
            }
            .padding(.horizontal, 14)
            palette
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Tiny Torii")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .padding(.trailing, 6)
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help("Undo")
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .help("Redo")
            Menu {
                Button("New Island") { model.newIsland() }
                Button("Grow a Sample Town") { model.sampleTown() }
                Divider()
                Button("Export Town…") { isExporting = true }
                Button("Import Town…") { isImporting = true }
            } label: {
                Image(systemName: "map")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            if !model.status.isEmpty {
                Text(model.status)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Time", selection: $model.time) {
                ForEach(TimeOfDay.allCases) { time in
                    Text(time.rawValue).tag(time)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button {
                model.mode = .explore
            } label: {
                Label("Explore", systemImage: "figure.walk")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.75, green: 0.2, blue: 0.13))
            .help("Walk through your town (X)")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var toolColumn: some View {
        VStack(spacing: 6) {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                Button {
                    model.choose(tool: tool)
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                        .background(model.tool == tool ? Color(red: 0.75, green: 0.2, blue: 0.13) : Color.clear, in: .rect(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("\(tool.rawValue) (\(index + 1)) — \(tool.help)")
            }
        }
        .padding(6)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.bottom, 10)
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Category.allCases) { category in
                    Button(category.rawValue) {
                        model.category = category
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(model.category == category ? Color.primary.opacity(0.12) : Color.clear, in: .capsule)
                }
                Spacer()
                Text(model.tool == .place ? model.kind.title : model.tool.help)
                    .italic()
                    .foregroundStyle(.secondary)
                if model.tool == .place, model.kind.styles.count > 1 {
                    Picker("Style", selection: $model.style) {
                        ForEach(Array(model.kind.styles.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Kind.kinds(in: model.category)) { kind in
                        Button {
                            model.choose(kind)
                        } label: {
                            VStack(spacing: 3) {
                                Thumbnail(kind: kind)
                                    .frame(width: 88, height: 66)
                                    .clipShape(.rect(cornerRadius: 7))
                                Text(kind.title)
                                    .font(.system(size: 12, design: .serif))
                                    .lineLimit(1)
                            }
                            .padding(4)
                            .foregroundStyle(isChosen(kind) ? Color.white : Color.primary)
                            .background(isChosen(kind) ? Color(red: 0.75, green: 0.2, blue: 0.13) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func isChosen(_ kind: Kind) -> Bool {
        model.tool == .place && model.kind == kind
    }

    // MARK: - Explore overlay

    private var exploreOverlay: some View {
        VStack {
            HStack {
                Button {
                    model.mode = .build
                } label: {
                    Label("Build", systemImage: "hammer")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.75, green: 0.2, blue: 0.13))
                Spacer()
                Text("W A S D to walk · arrows or drag to look · M to look with the mouse · Shift to hurry · Space to stroll · F to fly · Esc to build")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                Spacer()
                Picker("Time", selection: $model.time) {
                    ForEach(TimeOfDay.allCases) { time in
                        Text(time.rawValue).tag(time)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(14)
            Spacer()
            HStack(alignment: .bottom) {
                Joystick { model.explorer.stick = $0 }
                Spacer()
                StrollButton(explorer: model.explorer)
            }
            .padding(24)
        }
    }
}

// A rendered picture of a kind, from the package resources; the SF Symbol if it is missing.
private struct Thumbnail: View {
    let kind: Kind

    var body: some View {
        if let image = Self.image(for: kind) {
            Image(decorative: image, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: kind.symbol)
                .font(.system(size: 22))
        }
    }

    @MainActor private static var cache: [Kind: CGImage] = [:]

    @MainActor
    static func image(for kind: Kind) -> CGImage? {
        if let image = cache[kind] {
            return image
        }
        guard let url = kind.thumbnailURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        cache[kind] = image
        return image
    }
}

// Interaction3D's RTS controls in build mode: W A S D or arrows pan, Q/E rotate, R/F zoom, Shift hurries, the
// cursor at the window edge pans, Home resets.
private struct BuildCameraKeys: ViewModifier {
    let isEnabled: Bool
    @Binding var pose: RTSCameraPose

    func body(content: Content) -> some View {
        if isEnabled {
            content.rtsMovement(pose: $pose, settings: RTSMovementSettings(panSpeed: 0.6, distanceRange: 6...110))
        } else {
            content
        }
    }
}

private struct StrollButton: View {
    let explorer: Explorer
    @State private var isStrolling = false
    @State private var isFlying = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                explorer.isFlying = false
                explorer.isStrolling.toggle()
                refresh()
            } label: {
                Label(isStrolling ? "Stop" : "Stroll", systemImage: isStrolling ? "pause.fill" : "figure.walk.motion")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            Button {
                explorer.isFlying.toggle()
                refresh()
            } label: {
                Label(isFlying ? "Land" : "Fly", systemImage: isFlying ? "arrow.down.to.line" : "bird")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.5))
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func refresh() {
        isStrolling = explorer.isStrolling
        isFlying = explorer.isFlying
    }
}

private struct Joystick: View {
    let onChange: (SIMD2<Float>) -> Void
    @State private var offset: CGSize = .zero
    private let radius: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.25))
                .stroke(.white.opacity(0.5), lineWidth: 1.5)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .offset(offset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var translation = value.translation
                    let length = hypot(translation.width, translation.height)
                    if length > radius {
                        translation = CGSize(width: translation.width / length * radius, height: translation.height / length * radius)
                    }
                    offset = translation
                    onChange([Float(translation.width / radius), Float(-translation.height / radius)])
                }
                .onEnded { _ in
                    offset = .zero
                    onChange(.zero)
                }
        )
    }
}

struct TownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
