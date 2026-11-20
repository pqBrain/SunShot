import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// How the freeze overlay ended: Esc, ⌘C (copy to the clipboard) or the Studio button (open in the studio).
enum FreezeOutcome {
    case cancel, copy, studio
}

/// The frozen-screen capture overlay: the screen as it was when the shortcut was pressed, a small toolbar of
/// marking tools, and the area drag that finishes the capture. Marks are `Annotation`s in display points; building
/// them is `FreezeMarks` (Core), drawing them into the result is `FreezeComposer` (Render).
struct FreezeOverlayView: View {
    let frozen: CGImage
    let size: CGSize
    let finish: (FreezeOutcome, LayoutRect?, [Annotation]) -> Void
    let switchToWindow: () -> Void

    @State private var tool: FreezeTool = .area
    @State private var color = FreezePalette.colors[0]
    @State private var marks: [Annotation] = []
    @State private var path: [AnnotationPoint] = []
    @State private var selection: LayoutRect?
    /// The grip being dragged, or nil while the drag draws a mark or a new area; `dragging` is true mid-drag.
    @State private var activeHandle: SelectionHandle?
    @State private var dragging = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: frozen, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
            if let layer = FreezeComposer.markLayer(liveMarks, size: (size.width, size.height)) {
                Image(decorative: layer, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            dimming
            if let selection {
                Rectangle()
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.x, y: selection.y)
                    .allowsHitTesting(false)
                ForEach(SelectionHandle.allCases, id: \.self) { handle in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
                        .position(Self.position(of: handle, in: selection))
                        .allowsHitTesting(false)
                }
                Text(UIStrings.pixelSize(width: Int(selection.width), height: Int(selection.height)))
                    .font(.caption.monospacedDigit())
                    .padding(4)
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .offset(x: selection.x, y: max(0, selection.y - 24))
                    .allowsHitTesting(false)
            }
            toolbar
                .frame(width: size.width)
                .padding(.top, 24)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(drag)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handle(press) }
    }

    // MARK: Drawing

    private var liveMarks: [Annotation] {
        marks + [FreezeMarks.mark(tool: tool, path: path, color: color)].compactMap { $0 }
    }

    private var dimming: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let selection {
                path.addRect(CGRect(x: selection.x, y: selection.y, width: selection.width, height: selection.height))
            }
        }
        .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    // MARK: Input

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    activeHandle = selection.flatMap {
                        SelectionHandle.hit(rect: $0, point: (value.startLocation.x, value.startLocation.y))
                    }
                }
                if let handle = activeHandle, let current = selection {
                    selection = handle.resized(
                        current, to: (value.location.x, value.location.y), displayWidth: size.width,
                        displayHeight: size.height)
                } else if tool == .area {
                    selection = AreaSelection.rect(
                        from: (value.startLocation.x, value.startLocation.y), to: (value.location.x, value.location.y),
                        displayWidth: size.width, displayHeight: size.height)
                } else {
                    if path.isEmpty { path = [AnnotationPoint(x: value.startLocation.x, y: value.startLocation.y)] }
                    path.append(AnnotationPoint(x: value.location.x, y: value.location.y))
                }
            }
            .onEnded { _ in
                dragging = false
                if activeHandle != nil {
                    activeHandle = nil
                } else if tool == .area {
                    // The overlay stays: the selection is marked up, then ⌘C or Studio ends it.
                    if let rect = selection, AreaSelection.isCapturable(rect) {
                        tool = .arrow
                    } else {
                        selection = nil
                    }
                } else {
                    if let mark = FreezeMarks.mark(tool: tool, path: path, color: color) { marks.append(mark) }
                    path = []
                }
            }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            finish(.cancel, nil, [])
            return .handled
        }
        guard let key = press.characters.first else { return .ignored }
        if press.modifiers == .command, key == "z" {
            if !marks.isEmpty { marks.removeLast() }
            return .handled
        }
        if press.key == .return {
            end(.studio)
            return .handled
        }
        if press.modifiers == .command, key == "c" {
            end(.copy)
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }
        if press.key == .space, selection == nil, marks.isEmpty {
            switchToWindow()
            return .handled
        }
        if let next = FreezeTool.forShortcut(key) {
            tool = next
            return .handled
        }
        if let digit = key.wholeNumberValue, (1...FreezePalette.colors.count).contains(digit) {
            color = FreezePalette.colors[digit - 1]
            return .handled
        }
        return .ignored
    }

    private static func position(of handle: SelectionHandle, in rect: LayoutRect) -> CGPoint {
        let x: Double =
            switch handle {
            case .topLeft, .left, .bottomLeft: rect.x
            case .top, .bottom: rect.x + rect.width / 2
            default: rect.x + rect.width
            }
        let y: Double =
            switch handle {
            case .topLeft, .top, .topRight: rect.y
            case .left, .right: rect.y + rect.height / 2
            default: rect.y + rect.height
            }
        return CGPoint(x: x, y: y)
    }

    private func end(_ outcome: FreezeOutcome) {
        guard let selection, AreaSelection.isCapturable(selection) else { return }
        finish(outcome, selection, marks)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(FreezeTool.allCases, id: \.self) { item in
                Button {
                    tool = item
                } label: {
                    Image(systemName: Self.symbol(item))
                        .frame(width: 28, height: 28)
                        .background(tool == item ? Color.accentColor.opacity(0.35) : .clear, in: .rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(UIStrings.freezeToolName(item))
                .accessibilityLabel(UIStrings.freezeToolName(item))
            }
            Divider().frame(height: 20)
            ForEach(Array(FreezePalette.colors.enumerated()), id: \.offset) { _, swatch in
                Button {
                    color = swatch
                } label: {
                    Circle()
                        .fill(Color(.sRGB, red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white, lineWidth: color == swatch ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 20)
            Button {
                if !marks.isEmpty { marks.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(marks.isEmpty)
            .help(UIStrings.freezeUndo)
            .accessibilityLabel(UIStrings.freezeUndo)
            if selection != nil {
                Divider().frame(height: 20)
                Button(UIStrings.freezeCopy) { end(.copy) }
                    .buttonStyle(.plain)
                    .help(UIStrings.freezeCopyHelp)
                Button(UIStrings.freezeStudio) { end(.studio) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Text(selection == nil ? UIStrings.freezeHint : UIStrings.freezeMarkHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity)
    }

    private static func symbol(_ tool: FreezeTool) -> String {
        switch tool {
        case .area: "viewfinder"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        }
    }
}
