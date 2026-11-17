public import SunshotCore

/// Code-snippet edits. Each is one named undo step; edits that change nothing record nothing. Typing goes through
/// a gesture (see `EditorModel.setCode`), so a run of keystrokes becomes one "Typing" entry.
extension EditorSession {
    public static let newSnippetActionName = "New Code Snippet"
    public static let typingActionName = "Typing"
    public static let languageActionName = "Change Language"
    public static let codeThemeActionName = "Change Code Theme"
    public static let lineNumbersActionName = "Toggle Line Numbers"
    public static let highlightedLinesActionName = "Change Highlighted Lines"
    public static let snippetTitleActionName = "Change Snippet Title"
    public static let codeFontSizeActionName = "Change Code Font Size"
    public static let codePaddingActionName = "Change Code Padding"
    public static let resetCodeStyleActionName = "Reset Code Style"

    public var snippet: CodeSnippet? { document.snippet }

    /// Replaces the content (image or snippet) with `snippet`, keeping the style. One undo step.
    public mutating func newCodeSnippet(_ snippet: CodeSnippet = CodeSnippet()) {
        history.apply(Self.newSnippetActionName) {
            $0.content = nil
            $0.snippet = snippet
        }
    }

    /// Sets the code. Inside a gesture (typing run) it updates live; otherwise it is one "Typing" step.
    public mutating func setCode(_ code: String) {
        editSnippet(Self.typingActionName) { $0.code = code }
    }

    /// nil = auto-detect.
    public mutating func setLanguage(_ language: CodeLanguage?) {
        editSnippet(Self.languageActionName) { $0.language = language }
    }

    public mutating func setCodeTheme(_ id: String) {
        editSnippet(Self.codeThemeActionName) { $0.themeID = id }
    }

    public mutating func setShowLineNumbers(_ show: Bool) {
        editSnippet(Self.lineNumbersActionName) { $0.showLineNumbers = show }
    }

    public mutating func setHighlightedLines(_ lines: Set<Int>) {
        editSnippet(Self.highlightedLinesActionName) { $0.highlightedLines = lines }
    }

    /// Typed lines (`2, 4-6`). Returns false (nothing changes, no undo entry) when the text is invalid.
    @discardableResult
    public mutating func setHighlightedLines(text: String) -> Bool {
        guard let lines = HighlightedLines.parse(text) else { return false }
        setHighlightedLines(lines)
        return true
    }

    public mutating func setSnippetTitle(_ title: String) {
        editSnippet(Self.snippetTitleActionName) { $0.title = title }
    }

    public mutating func setCodeFontSize(_ size: Double) {
        editSnippet(Self.codeFontSizeActionName) { $0.fontSize = size }
    }

    public mutating func setCodePadding(_ padding: Double) {
        editSnippet(Self.codePaddingActionName) { $0.padding = padding }
    }

    /// Theme, line numbers, font size, padding and font back to defaults; code, language, title and highlighted
    /// lines are kept.
    public mutating func resetCodeStyle() {
        editSnippet(Self.resetCodeStyleActionName) { $0 = $0.resettingStyle() }
    }

    /// No-op for image documents.
    mutating func editSnippet(_ name: String, _ change: (inout CodeSnippet) -> Void) {
        guard document.snippet != nil else { return }
        let apply: (inout EditorDocument) -> Void = { document in
            guard var snippet = document.snippet else { return }
            change(&snippet)
            document.snippet = snippet
        }
        if history.isInGesture {
            history.updateGesture(name, apply)
        } else {
            history.applyIfChanged(name, apply)
        }
    }
}
