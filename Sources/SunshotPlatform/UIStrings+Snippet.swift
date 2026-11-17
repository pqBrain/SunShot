public import SunshotCore

/// S11: code snippet copy and accessibility labels.
extension UIStrings {
    public static let newCodeSnippet = "New Code Snippet"
    public static let newCodeSnippetAccessibility = "New Code Snippet, ⌥⌘N"
    public static let codeSection = "Code"
    public static let codePlaceholder = "Enter some code…"
    public static let codeEditorAccessibility = "Code editor"
    public static let autoDetect = "Auto-detect"
    public static let languagePicker = "Language"
    public static let themePicker = "Theme"
    public static let lineNumbersToggle = "Line numbers"
    public static let highlightedLinesField = "Highlighted lines"
    public static let highlightedLinesPlaceholder = "e.g. 2, 4-6"
    public static let highlightedLinesInvalid = "Use line numbers like 2, 4-6"
    public static let titleField = "Title"
    public static let titlePlaceholder = "Optional"
    public static let fontSizeSlider = "Font size"
    public static let codePaddingSlider = "Padding"

    public static func autoDetected(_ language: CodeLanguage) -> String { "\(autoDetect) (\(language.displayName))" }

    public static func languageAccessibility(_ snippet: CodeSnippet) -> String {
        let name = snippet.language?.displayName ?? autoDetected(snippet.effectiveLanguage)
        return "Language: \(name)"
    }

    public static func fontSizeAccessibility(_ size: Double) -> String {
        "Code font size, \(Int(size.rounded())) pixels"
    }

    public static func codePaddingAccessibility(_ padding: Double) -> String {
        "Code padding, \(Int(padding.rounded())) pixels"
    }

    public static func highlightedLinesAccessibility(_ text: String) -> String {
        text.isEmpty ? "Highlighted lines, none" : "Highlighted lines, \(text)"
    }
}
