import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Code section of the inspector (snippet documents only): language, theme, line numbers, highlighted lines,
/// title, font size and padding.
struct CodeSnippetControls: View {
    let model: EditorModel
    @State private var linesText = ""
    @State private var linesInvalid = false
    @State private var titleText = ""

    private var snippet: CodeSnippet { model.snippet ?? CodeSnippet() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(UIStrings.languagePicker) {
                Picker(
                    UIStrings.languagePicker,
                    selection: Binding(
                        get: { snippet.language }, set: { language in model.perform { $0.setLanguage(language) } })
                ) {
                    Text(model.autoDetectTitle).tag(CodeLanguage?.none)
                    Divider()
                    ForEach(CodeLanguage.allCases, id: \.self) { Text($0.displayName).tag(CodeLanguage?.some($0)) }
                }
                .labelsHidden()
                .accessibilityLabel(UIStrings.languageAccessibility(snippet))
            }

            LabeledContent(UIStrings.themePicker) {
                Picker(
                    UIStrings.themePicker,
                    selection: Binding(
                        get: { snippet.theme.id }, set: { id in model.perform { $0.setCodeTheme(id) } })
                ) {
                    ForEach(CodeTheme.catalog) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .accessibilityLabel("\(UIStrings.themePicker): \(snippet.theme.name)")
            }

            Toggle(
                UIStrings.lineNumbersToggle,
                isOn: Binding(
                    get: { snippet.showLineNumbers }, set: { show in model.perform { $0.setShowLineNumbers(show) } }))

            VStack(alignment: .leading, spacing: 4) {
                ControlCaption(UIStrings.highlightedLinesField)
                TextField(UIStrings.highlightedLinesPlaceholder, text: $linesText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        linesInvalid = !model.setHighlightedLines(text: linesText)
                        if !linesInvalid { linesText = model.highlightedLinesText }
                    }
                    .accessibilityLabel(UIStrings.highlightedLinesAccessibility(model.highlightedLinesText))
                if linesInvalid {
                    Text(UIStrings.highlightedLinesInvalid)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ControlCaption(UIStrings.titleField)
                TextField(UIStrings.titlePlaceholder, text: $titleText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: titleText) { _, value in model.setSnippetTitle(value) }
                    .accessibilityLabel(UIStrings.titleField)
            }

            slider(
                UIStrings.fontSizeSlider, value: snippet.fontSize, range: CodeSnippet.fontSizeRange,
                actionName: EditorSession.codeFontSizeActionName,
                label: UIStrings.fontSizeAccessibility(snippet.fontSize)
            ) { session, value in session.setCodeFontSize(value) }

            slider(
                UIStrings.codePaddingSlider, value: snippet.padding, range: CodeSnippet.paddingRange,
                actionName: EditorSession.codePaddingActionName,
                label: UIStrings.codePaddingAccessibility(snippet.padding)
            ) { session, value in session.setCodePadding(value) }
        }
        .onAppear(perform: syncFields)
        .onChange(of: snippet.highlightedLines) { _, _ in linesText = model.highlightedLinesText }
        .onChange(of: snippet.title) { _, value in if value != titleText { titleText = value } }
    }

    private func syncFields() {
        linesText = model.highlightedLinesText
        titleText = snippet.title
    }

    private func slider(
        _ title: String, value: Double, range: ClosedRange<Double>, actionName: String, label: String,
        set: @escaping (inout EditorSession, Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ControlCaption(title)
                Spacer()
                Text("\(Int(value.rounded())) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            Slider(
                value: Binding(get: { value }, set: { new in model.perform { set(&$0, new.rounded()) } }),
                in: range
            ) {
                Text(title)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(actionName)
            }
            .labelsHidden()
            .accessibilityLabel(label)
        }
    }
}
