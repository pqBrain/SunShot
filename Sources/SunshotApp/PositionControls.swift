import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Floating bar at the bottom of the canvas with the Position control.
struct BottomToolbar: View {
    let model: EditorModel
    @State private var showsPosition = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showsPosition.toggle()
            } label: {
                Label(UIStrings.positionButton, systemImage: "move.3d")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glass)
            .help(UIStrings.positionButtonAccessibility)
            .accessibilityLabel(UIStrings.positionButtonAccessibility)
            .disabled(!model.hasContent)
            .popover(isPresented: $showsPosition, arrowEdge: .top) { PositionPopover(model: model) }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 14)
    }
}

/// Position / Tilt tabs, zoom and rotation, and Reset.
struct PositionPopover: View {
    let model: EditorModel
    @State private var tab = Tab.position

    enum Tab: Hashable { case position, tilt }

    private var transform: ContentTransform { model.session.contentTransform }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: $tab) {
                    Text(UIStrings.positionTab).tag(Tab.position)
                    Text(UIStrings.tiltTab).tag(Tab.tilt)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    model.perform { $0.resetPosition() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .help(UIStrings.resetPosition)
                .accessibilityLabel(UIStrings.resetPosition)
                .disabled(transform.isIdentity)
            }
            switch tab {
            case .position: PositionPad(model: model)
            case .tilt: TiltControls(model: model)
            }
            ValueSlider(
                title: UIStrings.zoomLabel, unit: "%", value: transform.zoom, range: ContentTransform.zoomRange,
                accessibility: UIStrings.zoom(transform.zoom), actionName: EditorSession.zoomActionName, model: model,
                set: { value in model.perform { $0.setZoom(value) } }, setText: { model.setZoom(text: $0) })
            ValueSlider(
                title: UIStrings.rotationLabel, unit: "°", value: transform.rotation,
                range: ContentTransform.rotationRange, accessibility: UIStrings.rotation(transform.rotation),
                actionName: EditorSession.rotateActionName, model: model,
                set: { value in model.perform { $0.setRotation(value.rounded()) } },
                setText: { model.setRotation(text: $0) })
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// A labelled slider with a typed value field; a drag is one undo step.
struct ValueSlider: View {
    let title: String
    let unit: String
    let value: Double
    let range: ClosedRange<Double>
    let accessibility: String
    let actionName: String
    let model: EditorModel
    let set: @MainActor (Double) -> Void
    let setText: @MainActor (String) -> Bool
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value }, set: set), in: range) {
                    Text(title)
                } onEditingChanged: { editing in
                    editing ? model.beginGesture() : model.endGesture(actionName)
                }
                .labelsHidden()
                .accessibilityLabel(accessibility)
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .onSubmit { if !setText(text) { text = Self.format(value) } }
                    .accessibilityLabel(accessibility)
                Text(unit).font(.callout).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { _, newValue in text = Self.format(newValue) }
    }

    static func format(_ value: Double) -> String { String(Int(value.rounded())) }
}

/// Mini canvas with a draggable handle at the content centre. Arrow keys nudge it (⇧ for bigger steps).
struct PositionPad: View {
    let model: EditorModel
    @FocusState private var isFocused: Bool
    @State private var isDragging = false

    private var transform: ContentTransform { model.session.contentTransform }

    var body: some View {
        let size = surfaceSize
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let preview = model.preview {
                    Image(decorative: preview, scale: 1).resizable().interpolation(.medium)
                } else {
                    Rectangle().fill(.black.opacity(0.08))
                }
                GuideLines(guides: model.layout.guides, size: size)
                Circle()
                    .fill(Color.accentColor)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: isDragging ? 5 : 2)
                    .position(x: (0.5 + transform.x) * size.width, y: (0.5 + transform.y) * size.height)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor : Color(nsColor: SunshotPalette.controlStroke),
                        lineWidth: isFocused ? 2 : 1)
            }
            .contentShape(.rect)
            .gesture(drag(size: size))
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let large = press.modifiers.contains(.shift)
                switch press.key {
                case .leftArrow: model.nudgePosition(dx: -1, dy: 0, large: large)
                case .rightArrow: model.nudgePosition(dx: 1, dy: 0, large: large)
                case .upArrow: model.nudgePosition(dx: 0, dy: -1, large: large)
                default: model.nudgePosition(dx: 0, dy: 1, large: large)
                }
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel(UIStrings.contentPosition(x: transform.x, y: transform.y))
            .accessibilityAdjustableAction { direction in
                model.nudgePosition(dx: direction == .increment ? 1 : -1, dy: 0, large: false)
            }
            Text(UIStrings.positionHint).font(.caption).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
        }
    }

    /// The canvas aspect ratio fitted into 248 × 160.
    private var surfaceSize: CGSize {
        let canvas = model.session.canvasSize ?? PixelSize(width: 16, height: 10)
        let scale = min(248 / Double(canvas.width), 160 / Double(canvas.height))
        return CGSize(width: Double(canvas.width) * scale, height: Double(canvas.height) * scale)
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    model.beginPositionDrag(surfaceWidth: size.width, surfaceHeight: size.height)
                }
                let flags = NSEvent.modifierFlags
                var modifiers: DragModifiers = []
                if flags.contains(.option) { modifiers.insert(.option) }
                if flags.contains(.command) { modifiers.insert(.command) }
                model.updatePositionDrag(
                    translationX: value.translation.width, translationY: value.translation.height, modifiers: modifiers)
            }
            .onEnded { _ in
                isDragging = false
                model.endPositionDrag()
            }
    }
}

/// Snap and axis-lock guides on the mini canvas.
struct GuideLines: View {
    let guides: [PositionGuide]
    let size: CGSize

    var body: some View {
        Path { path in
            for guide in guides {
                switch guide {
                case .axisLock(.horizontal, let through): horizontal(&path, y: (0.5 + through) * size.height)
                case .axisLock(.vertical, let through): vertical(&path, x: (0.5 + through) * size.width)
                case .centerX: vertical(&path, x: size.width / 2)
                case .centerY: horizontal(&path, y: size.height / 2)
                case .leftEdge: vertical(&path, x: 1)
                case .rightEdge: vertical(&path, x: size.width - 1)
                case .topEdge: horizontal(&path, y: 1)
                case .bottomEdge: horizontal(&path, y: size.height - 1)
                }
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    private func horizontal(_ path: inout Path, y: Double) {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
    }

    private func vertical(_ path: inout Path, x: Double) {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
    }
}

/// Square pad: drag toward an edge to tilt (edge = ±30°), plus sliders for the full ±60°.
struct TiltControls: View {
    let model: EditorModel
    @State private var isDragging = false
    private let side: CGFloat = 132

    private var transform: ContentTransform { model.session.contentTransform }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                pad
                Spacer()
            }
            Text(UIStrings.tiltHint).font(.caption).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            tiltSlider(UIStrings.tiltXLabel, value: transform.tiltX) { value in
                model.perform { $0.setTilt(x: value.rounded(), y: transform.tiltY) }
            }
            tiltSlider(UIStrings.tiltYLabel, value: transform.tiltY) { value in
                model.perform { $0.setTilt(x: transform.tiltX, y: value.rounded()) }
            }
        }
    }

    private var pad: some View {
        let handle = TiltPad.handle(for: transform)
        let half = side / 2
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.08))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .frame(width: 54, height: 38)
                .rotation3DEffect(.degrees(transform.tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(-transform.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            Circle()
                .fill(Color.accentColor)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .frame(width: 16, height: 16)
                .position(x: half + handle.x * (half - 10), y: half + handle.y * (half - 10))
        }
        .frame(width: side, height: side)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        model.beginGesture()
                    }
                    let tilt = TiltPad.tilt(
                        handleX: (value.location.x - half) / (half - 10),
                        handleY: (value.location.y - half) / (half - 10))
                    model.perform { $0.setTilt(x: tilt.tiltX.rounded(), y: tilt.tiltY.rounded()) }
                }
                .onEnded { _ in
                    isDragging = false
                    model.endGesture(EditorSession.tiltActionName)
                }
        )
        .accessibilityElement()
        .accessibilityLabel(UIStrings.tilt(x: transform.tiltX, y: transform.tiltY))
    }

    private func tiltSlider(_ title: String, value: Double, set: @escaping @MainActor (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.callout).frame(width: 48, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: ContentTransform.tiltRange) {
                Text(title)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(EditorSession.tiltActionName)
            }
            .labelsHidden()
            Text("\(Int(value.rounded()))°").font(.callout.monospacedDigit()).frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Int(value.rounded())) degrees")
    }
}
