import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Transparent layer over the canvas preview in Annotate mode: turns pointer and key input into model calls and
/// shows the selection chrome. It draws no document pixels — annotations appear through the shared renderer.
struct AnnotationOverlay: View {
    @Bindable var model: EditorModel
    @State private var isPressing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(pointerGesture(width: width, height: height))
                ForEach(model.selectionOutlines(viewWidth: width, viewHeight: height)) { outline in
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .frame(width: outline.width + 8, height: outline.height + 8)
                        .rotationEffect(.degrees(outline.rotation))
                        .position(x: outline.centerX, y: outline.centerY)
                        .allowsHitTesting(false)
                }
                ForEach(model.selectionHandles(viewWidth: width, viewHeight: height), id: \.self) { mark in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: AnnotationDefaults.handleRadius * 2, height: AnnotationDefaults.handleRadius * 2)
                        .position(x: mark.x, y: mark.y)
                        .allowsHitTesting(false)
                }
                if let placement = model.textEditorPlacement(viewWidth: width, viewHeight: height) {
                    AnnotationTextField(model: model, fontSize: placement.fontSize)
                        .offset(x: placement.x, y: placement.y)
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
        .accessibilityElement()
        .accessibilityLabel(UIStrings.annotationCanvas)
    }

    private func pointerGesture(width: Double, height: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    isFocused = model.annotate.textEditing == nil
                    model.annotationPointerDown(
                        x: value.startLocation.x, y: value.startLocation.y, viewWidth: width, viewHeight: height,
                        additive: NSEvent.modifierFlags.contains(.command),
                        clickCount: NSApp.currentEvent?.clickCount ?? 1)
                }
                model.annotationPointerDragged(
                    x: value.location.x, y: value.location.y, viewWidth: width, viewHeight: height,
                    snap: NSEvent.modifierFlags.contains(.shift))
            }
            .onEnded { _ in
                isPressing = false
                model.annotationPointerUp()
            }
    }

    private func handle(_ press: KeyPress) -> Bool {
        guard !press.modifiers.contains(.command) else { return false }
        if press.key == .escape { return model.handleAnnotateKey(.escape) }
        if press.key == .delete || press.key == .deleteForward { return model.handleAnnotateKey(.delete) }
        guard let character = press.characters.first else { return false }
        return model.handleAnnotateKey(.character(character), shift: press.modifiers.contains(.shift))
    }
}

/// In-place editor for a text annotation. Return commits, ⌥Return adds a line, Esc cancels.
struct AnnotationTextField: View {
    @Bindable var model: EditorModel
    let fontSize: Double
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            UIStrings.textPlaceholder,
            text: Binding(
                get: { model.annotate.textEditing?.text ?? "" },
                set: { model.annotate.textEditing?.text = $0 }),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: max(9, fontSize)))
        .foregroundStyle(Color(nsColor: model.annotate.style.color.nsColor))
        .frame(minWidth: 160, alignment: .leading)
        .fixedSize()
        .padding(2)
        .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onSubmit { model.commitTextEditing() }
        .onExitCommand { model.cancelTextEditing() }
    }
}
