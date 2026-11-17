import SunshotCore
import SunshotPlatform
import SwiftUI

/// S16: the annotation bar, a glass bar at the top of the canvas that is always there for screenshots. Picking a
/// tool enters Annotate mode; Done leaves it.
struct AnnotationPalette: View {
    @Bindable var model: EditorModel
    @State private var showsColors = false

    private var editor: AnnotationEditor { model.annotate }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }
            }
            Divider().frame(height: 22)
            colorButton
            Picker(UIStrings.annotationSize, selection: sizeBinding) {
                ForEach(AnnotationSize.allCases, id: \.self) { Text(UIStrings.sizeName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            .help(UIStrings.annotationSize + ", [ ]")
            .accessibilityLabel(UIStrings.annotationSize)
            lineStyleMenu
            Toggle(isOn: Binding(get: { editor.style.filled }, set: { model.setAnnotationFilled($0) })) {
                Image(systemName: "square.fill")
            }
            .toggleStyle(.button)
            .help(UIStrings.fill + ", F")
            .accessibilityLabel(UIStrings.fill)
            contextualControls
            Divider().frame(height: 22)
            Button(UIStrings.clearAnnotations) { model.clearAnnotations() }
                .disabled(!model.hasAnnotations)
            if editor.isActive {
                Button(UIStrings.doneAnnotating) { model.setAnnotateMode(false) }
                    .buttonStyle(.glassProminent)
                    .help(UIStrings.doneAnnotatingAccessibility)
                    .accessibilityLabel(UIStrings.doneAnnotatingAccessibility)
            }
        }
        .disabled(!model.isAnnotationBarEnabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.toolPalette)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button {
            model.pickAnnotationTool(tool)
        } label: {
            Image(systemName: UIStrings.toolSymbol(tool))
                .frame(width: 26, height: 26)
                .background(
                    isCurrent(tool) ? Color.accentColor.opacity(0.22) : Color.clear, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(UIStrings.toolLabel(tool))
        .accessibilityLabel(UIStrings.toolLabel(tool))
        .accessibilityAddTraits(isCurrent(tool) ? .isSelected : [])
        .popover(
            isPresented: Binding(
                get: { tool == .sticker && editor.showsStickerPicker },
                set: { model.annotate.showsStickerPicker = $0 })
        ) { StickerPicker(model: model) }
    }

    private func isCurrent(_ tool: AnnotationTool) -> Bool { editor.isActive && editor.tool == tool }

    private var colorButton: some View {
        Button {
            showsColors.toggle()
        } label: {
            Circle()
                .fill(Color(nsColor: editor.style.color.nsColor))
                .overlay(Circle().stroke(Color.primary.opacity(0.25)))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(UIStrings.annotationColor)
        .accessibilityLabel(UIStrings.annotationColor)
        .accessibilityValue(editor.style.color.hexString)
        .popover(isPresented: $showsColors) { AnnotationColorGrid(model: model) }
    }

    private var lineStyleMenu: some View {
        Picker(UIStrings.lineStyle, selection: lineStyleBinding) {
            ForEach(AnnotationLineStyle.allCases, id: \.self) { Text(UIStrings.lineStyleName($0)).tag($0) }
        }
        .labelsHidden()
        .frame(width: 120)
        .help(UIStrings.lineStyle)
        .accessibilityLabel(UIStrings.lineStyle)
    }

    @ViewBuilder private var contextualControls: some View {
        switch editor.tool {
        case .redact:
            Picker(UIStrings.redactionMode, selection: redactionBinding) {
                ForEach(RedactionMode.allCases, id: \.self) { Text(UIStrings.redactionName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
            .accessibilityLabel(UIStrings.redactionMode)
        case .step:
            Picker(UIStrings.stepFormat, selection: stepBinding) {
                ForEach(StepFormat.allCases, id: \.self) { Text(UIStrings.stepFormatName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
            .accessibilityLabel(UIStrings.stepFormat)
        case .text:
            Picker(UIStrings.alignmentName(editor.style.alignment), selection: alignmentBinding) {
                ForEach(AnnotationTextAlignment.allCases, id: \.self) { Text(UIStrings.alignmentName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
        default:
            EmptyView()
        }
    }

    private var sizeBinding: Binding<AnnotationSize> {
        Binding(get: { editor.style.size }, set: { model.setAnnotationSize($0) })
    }
    private var lineStyleBinding: Binding<AnnotationLineStyle> {
        Binding(get: { editor.style.lineStyle }, set: { model.setAnnotationLineStyle($0) })
    }
    private var redactionBinding: Binding<RedactionMode> {
        Binding(get: { editor.style.redaction }, set: { model.setRedactionMode($0) })
    }
    private var stepBinding: Binding<StepFormat> {
        Binding(get: { model.stepFormat }, set: { model.setStepFormat($0) })
    }
    private var alignmentBinding: Binding<AnnotationTextAlignment> {
        Binding(get: { editor.style.alignment }, set: { model.setTextAlignment($0) })
    }
}

/// The 20 palette colours plus a custom colour well.
struct AnnotationColorGrid: View {
    let model: EditorModel
    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AnnotationDefaults.palette, id: \.self) { entry in
                    Button {
                        model.setAnnotationColor(entry.color)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: entry.color.nsColor))
                            .overlay(Circle().stroke(Color.primary.opacity(0.2)))
                            .overlay(
                                Circle().stroke(
                                    Color.accentColor, lineWidth: model.annotate.style.color == entry.color ? 2 : 0
                                ).padding(-3)
                            )
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.name)
                }
            }
            ColorPicker(
                UIStrings.customAnnotationColor,
                selection: Binding(
                    get: { Color(nsColor: model.annotate.style.color.nsColor) },
                    set: { newValue in
                        guard let picked = RGBAColor(nsColor: NSColor(newValue)) else { return }
                        model.setAnnotationColor(picked)
                    }),
                supportsOpacity: true)
        }
        .padding(14)
    }
}

struct StickerPicker: View {
    let model: EditorModel
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(AnnotationDefaults.stickers, id: \.self) { emoji in
                Button {
                    model.chooseSticker(emoji)
                } label: {
                    Text(emoji).font(.system(size: 24)).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
            }
        }
        .padding(12)
    }
}
