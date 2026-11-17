import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Frame section: eight frame tiles (live thumbnails), title field and UI scale.
struct FrameControls: View {
    let model: EditorModel

    private var frame: Frame { model.project.frame }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(FrameKind.allCases, id: \.self) { kind in
                    FrameTile(kind: kind, image: model.frameThumbnail(kind), isSelected: frame.kind == kind) {
                        model.perform { $0.setFrameKind(kind) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(UIStrings.frameSection)

            if frame.kind.hasTitle {
                FrameTitleField(model: model)
            }
            if frame.kind != .none {
                UIScaleControl(model: model)
            }
        }
        .animation(.smooth(duration: 0.2), value: frame.kind)
    }
}

struct FrameTile: View {
    let kind: FrameKind
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .padding(4)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color(nsColor: SunshotPalette.selectionRing) : .clear, lineWidth: 2)
                }
                Text(UIStrings.frameName(kind))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UIStrings.frameOption(kind, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Title field: typing updates the preview live; Return commits one undo step; Esc restores the old title.
struct FrameTitleField: View {
    let model: EditorModel
    @State private var text = ""
    @State private var original: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ControlCaption(UIStrings.frameTitle)
            TextField(UIStrings.frameTitlePlaceholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: text) { _, value in
                    guard focused, value != model.project.frame.title else { return }
                    if original == nil {
                        original = model.project.frame.title
                        model.beginTitleEdit()
                    }
                    model.updateTitle(value)
                }
                .onSubmit(commit)
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .accessibilityLabel(UIStrings.frameTitle)
                .accessibilityValue(model.project.frame.title)
        }
        .onAppear { text = model.project.frame.title }
        .onChange(of: model.project.frame.title) { _, value in if original == nil { text = value } }
    }

    private func commit() {
        guard original != nil else { return }
        original = nil
        model.commitTitleEdit()
        text = model.project.frame.title
    }

    private func cancel() {
        guard let previous = original else { return }
        original = nil
        model.cancelTitleEdit(restoring: previous)
        text = previous
    }
}

struct UIScaleControl: View {
    let model: EditorModel

    private var scale: Double { model.project.frame.uiScale }

    var body: some View {
        HStack(spacing: 10) {
            ControlCaption(UIStrings.uiScaleLabel)
            Slider(
                value: Binding(get: { scale }, set: { value in model.perform { $0.setUIScale(value) } }),
                in: Frame.uiScaleRange, step: 1
            ) {
                Text(UIStrings.uiScaleLabel)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(EditorSession.uiScaleActionName)
            }
            .labelsHidden()
            .accessibilityLabel(UIStrings.uiScaleLabel)
            .accessibilityValue(UIStrings.uiScale(scale))
            Text("\(Int(scale)) %")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

/// Double-click the title bar on the canvas to edit the title in place (Return commits, Esc cancels).
struct FrameTitleOverlay: View {
    let model: EditorModel
    @State private var isEditing = false
    @State private var text = ""
    @State private var original = ""
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            if let unit = model.titleBarUnitRect {
                let rect = CGRect(
                    x: unit.minX * proxy.size.width, y: unit.minY * proxy.size.height,
                    width: unit.width * proxy.size.width, height: unit.height * proxy.size.height)
                Group {
                    if isEditing {
                        TextField(UIStrings.frameTitlePlaceholder, text: $text)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: max(9, rect.height * 0.45)))
                            .padding(.horizontal, 6)
                            .background(.regularMaterial, in: .rect(cornerRadius: 4))
                            .padding(.horizontal, rect.height * 2.6)
                            .padding(.vertical, rect.height * 0.15)
                            .focused($focused)
                            .onChange(of: text) { _, value in model.updateTitle(value) }
                            .onSubmit { finish(commit: true) }
                            .onKeyPress(.escape) {
                                finish(commit: false)
                                return .handled
                            }
                            .onChange(of: focused) { _, isFocused in if !isFocused { finish(commit: true) } }
                    } else {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(count: 2, perform: start)
                            .help(UIStrings.editTitleHint)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func start() {
        original = model.project.frame.title
        text = original
        model.beginTitleEdit()
        isEditing = true
        focused = true
    }

    private func finish(commit: Bool) {
        guard isEditing else { return }
        isEditing = false
        if commit { model.commitTitleEdit() } else { model.cancelTitleEdit(restoring: original) }
    }
}
