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
    @AppStorage("showsFrameTiming") private var showsFrameTiming = false
    @State private var viewSize: CGSize = .zero
    @State private var lastLook: CGSize = .zero
    @State private var isExporting = false
    // Made when Export is chosen, not on every redraw.
    @State private var exportDocument: TownDocument?
    @State private var isImporting = false
    @FocusState private var isFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

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
        .modifier(KeyboardFocus(isFocused: $isFocused, model: model, handleKey: handleKey))
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentType: .json, defaultFilename: "Town") { _ in
            exportDocument = nil
        }
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

    private var sceneViewOptions: SceneView.Options {
        // No SceneView camera control: Interaction3D's RTS controls are the build camera (see BuildCameraKeys).
        var options: SceneView.Options = []
        if showsFrameTiming {
            options.insert(.showsFrameTiming)
        }
        return options
    }

    private var sceneView: some View {
        SceneView(
            sceneGraph: model.scene.sceneGraph,
            pointOfView: model.mode == .explore ? model.explorer.cameraNode : nil,
            options: sceneViewOptions,
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
        .modifier(BuildCameraKeys(isEnabled: model.mode == .build, pose: $model.rtsPose, brushFilter: BrushDragFilter(model: model, viewSize: viewSize)))
        .modifier(ExploreMovement(navigator: model.mode == .explore ? model.explorer.navigator : nil))
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

    // iPhone-sized: narrow (portrait) or short (landscape).
    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact || verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var isPhoneLandscape: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private static let accent = Color(red: 0.75, green: 0.2, blue: 0.13)

    private var buildOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if isCompact {
                // Tools go in the palette as a row; a column would cover the scene.
                palette
            } else {
                HStack(alignment: .bottom) {
                    toolColumn
                    Spacer()
                }
                .padding(.horizontal, 14)
                palette
            }
        }
    }

    private var undoButtons: some View {
        Group {
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
        }
    }

    private var mapMenu: some View {
        Menu {
            Button("New Island") { model.newIsland() }
            Button("Grow a Sample Town") { model.sampleTown() }
            Divider()
            Button("Export Town…") {
                exportDocument = (try? model.export()).map(TownDocument.init(data:))
                isExporting = exportDocument != nil
            }
            Button("Import Town…") { isImporting = true }
            Divider()
            Toggle("Show Frame Rate", isOn: $showsFrameTiming)
        } label: {
            Image(systemName: "map")
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // A segmented picker where there is room, a menu where there isn't.
    @ViewBuilder
    private var timePicker: some View {
        if isCompact {
            Menu {
                Picker("Time", selection: $model.time) {
                    ForEach(TimeOfDay.allCases) { time in
                        Label(time.rawValue, systemImage: time.symbol).tag(time)
                    }
                }
            } label: {
                Image(systemName: model.time.symbol)
            }
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            Picker("Time", selection: $model.time) {
                ForEach(TimeOfDay.allCases) { time in
                    Text(time.rawValue).tag(time)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var exploreButton: some View {
        Button {
            model.mode = .explore
        } label: {
            if isCompact {
                Image(systemName: "figure.walk")
            } else {
                Label("Explore", systemImage: "figure.walk")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.accent)
        .help("Walk through your town (X)")
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if !isCompact {
                Text("Tiny Torii")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .padding(.trailing, 6)
            }
            undoButtons
            mapMenu
            Spacer(minLength: 4)
            if !model.status.isEmpty {
                Text(model.status)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            timePicker
            exploreButton
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, isCompact ? 10 : 16)
        .padding(.vertical, isCompact ? 6 : 10)
        .background(.regularMaterial, ignoresSafeAreaEdges: .top)
    }

    private func toolButton(_ tool: Tool, index: Int, size: CGFloat) -> some View {
        Button {
            model.choose(tool: tool)
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: size * 0.5))
                .frame(width: size, height: size)
                .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                .background(model.tool == tool ? Self.accent : Color.clear, in: .rect(cornerRadius: size * 0.22))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(tool.rawValue) (\(index + 1)) — \(tool.help)")
        .accessibilityLabel(tool.rawValue)
    }

    private var toolColumn: some View {
        VStack(spacing: 6) {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                toolButton(tool, index: index, size: 40)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.bottom, 10)
    }

    private var toolRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                toolButton(tool, index: index, size: 38)
            }
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Category.allCases) { category in
                    Button(category.rawValue) {
                        model.category = category
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, isCompact ? 10 : 12)
                    .padding(.vertical, 5)
                    .background(model.category == category ? Color.primary.opacity(0.12) : Color.clear, in: .capsule)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var stylePicker: some View {
        if model.tool == .place, model.kind.styles.count > 1 {
            if isCompact {
                Picker("Style", selection: $model.style) {
                    ForEach(Array(model.kind.styles.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } else {
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
    }

    private var kindStrip: some View {
        let width: CGFloat = isPhoneLandscape ? 60 : (isCompact ? 68 : 88)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isCompact ? 6 : 8) {
                ForEach(Kind.kinds(in: model.category)) { kind in
                    Button {
                        model.choose(kind)
                    } label: {
                        VStack(spacing: 3) {
                            Thumbnail(kind: kind)
                                .frame(width: width, height: width * 0.75)
                                .clipShape(.rect(cornerRadius: 7))
                            Text(kind.title)
                                .font(.system(size: isCompact ? 11 : 12, design: .serif))
                                .lineLimit(1)
                                .frame(width: width)
                        }
                        .padding(4)
                        .foregroundStyle(isChosen(kind) ? Color.white : Color.primary)
                        .background(isChosen(kind) ? Self.accent : Color.primary.opacity(0.06), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            if isCompact {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        toolRow
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    stylePicker
                }
                categoryTabs
            } else {
                HStack(spacing: 6) {
                    categoryTabs
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                    Text(model.tool == .place ? model.kind.title : model.tool.help)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    stylePicker
                }
            }
            kindStrip
        }
        .padding(.horizontal, isCompact ? 10 : 16)
        .padding(.vertical, isCompact ? 6 : 10)
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
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
                .tint(Self.accent)
                Spacer()
                if !isCompact {
                    Text("W A S D to walk · arrows or drag to look · M to look with the mouse · Shift to hurry · Space to stroll · F to fly · Esc to build")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .lineLimit(2)
                    Spacer()
                }
                timePicker
                    .buttonStyle(.bordered)
            }
            .padding(isCompact ? 10 : 14)
            Spacer()
            HStack(alignment: .bottom) {
                Joystick { model.explorer.stick = $0 }
                Spacer()
                StrollButton(explorer: model.explorer, isCompact: isCompact)
            }
            .padding(isCompact ? 14 : 24)
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

// Focus and key handling for the whole view.
private struct KeyboardFocus: ViewModifier {
    var isFocused: FocusState<Bool>.Binding
    let model: TownModel
    let handleKey: (KeyPress) -> KeyPress.Result

    func body(content: Content) -> some View {
        // In explore mode Interaction3D's .fpvMovement takes focus and claims the movement keys; other keys still
        // reach this handler.
        content
            .focusable(model.mode == .build)
            .focusEffectDisabled()
            .focused(isFocused)
            .onAppear { isFocused.wrappedValue = model.mode == .build }
            .onChange(of: model.mode) { isFocused.wrappedValue = model.mode == .build }
            .onKeyPress(phases: [.down, .up]) { press in
                handleKey(press)
            }
    }
}

// Leaves drags that the brush paints with (they start on the island while a painting tool is chosen) to the brush.
private struct BrushDragFilter: InteractionLocationFilter {
    let model: TownModel
    let viewSize: CGSize

    func accepts(_ location: CGPoint) -> Bool {
        !model.brushClaimsDrag(at: [Float(location.x), Float(location.y)], viewSize: [Float(viewSize.width), Float(viewSize.height)])
    }
}

// Interaction3D's FPV walking in explore mode, driven from the scene view's frame loop.
private struct ExploreMovement: ViewModifier {
    let navigator: FPVNavigator?

    func body(content: Content) -> some View {
        if let navigator {
            content.fpvMovement(navigator, updatesAutomatically: false)
        } else {
            content
        }
    }
}

// Interaction3D's RTS controls in build mode: drag pans, Option-drag orbits, scroll or pinch zooms; W A S D or arrows
// pan, Q/E rotate, R/F zoom, Shift hurries, the cursor at the window edge pans, Home resets.
private struct BuildCameraKeys: ViewModifier {
    let isEnabled: Bool
    @Binding var pose: RTSCameraPose
    let brushFilter: BrushDragFilter

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .rtsMovement(pose: $pose, settings: RTSMovementSettings(panSpeed: 0.6, distanceRange: 6...110))
                .interactionDragFilter(brushFilter)
        } else {
            content
        }
    }
}

private struct StrollButton: View {
    let explorer: Explorer
    var isCompact = false
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
                    .labelStyle(.adaptive(iconOnly: isCompact))
                    .padding(.horizontal, isCompact ? 4 : 10)
                    .padding(.vertical, 6)
            }
            Button {
                explorer.isFlying.toggle()
                refresh()
            } label: {
                Label(isFlying ? "Land" : "Fly", systemImage: isFlying ? "arrow.down.to.line" : "bird")
                    .labelStyle(.adaptive(iconOnly: isCompact))
                    .padding(.horizontal, isCompact ? 4 : 10)
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

private struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}

private extension LabelStyle where Self == AdaptiveLabelStyle {
    static func adaptive(iconOnly: Bool) -> AdaptiveLabelStyle {
        AdaptiveLabelStyle(iconOnly: iconOnly)
    }
}
