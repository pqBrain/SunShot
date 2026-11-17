public import SunshotCore
import SunshotRender

/// S11: code-snippet documents. Discrete edits go through `perform`; typing and the title field stream through
/// `performContinuous`, so a run of keystrokes is one undo step.
extension EditorModel {
    /// A typing run closes (becomes one "Typing" undo step) after this long without a keystroke.
    public static let typingIdle: Duration = .seconds(1)

    public var snippet: CodeSnippet? { session.snippet }
    public var isSnippet: Bool { session.snippet != nil }

    /// Replaces the content with a new snippet (one undo step "New Code Snippet").
    @discardableResult
    public func newCodeSnippet() -> Task<Void, Never> {
        perform { $0.newCodeSnippet() }
    }

    /// Text from the code editor. Keystrokes less than `idle` apart merge into one "Typing" undo step.
    public func setCode(_ code: String, idle: Duration = EditorModel.typingIdle) {
        guard isSnippet, code != snippet?.code else { return }
        performContinuous(EditorSession.typingActionName, idle: idle) { $0.setCode(code) }
    }

    /// Text from the title field, merged like typing.
    public func setSnippetTitle(_ title: String, idle: Duration = EditorModel.typingIdle) {
        guard isSnippet, title != snippet?.title else { return }
        performContinuous(EditorSession.snippetTitleActionName, idle: idle) { $0.setSnippetTitle(title) }
    }

    /// Typed highlighted lines (`2, 4-6`). Returns false (nothing changes) when the text is invalid.
    @discardableResult
    public func setHighlightedLines(text: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setHighlightedLines(text: text) }
        return accepted
    }

    /// The highlighted lines as the field shows them: `2, 4–6`.
    public var highlightedLinesText: String { HighlightedLines.format(snippet?.highlightedLines ?? []) }

    /// Picker label for auto-detect, naming what was detected: "Auto-detect (Swift)".
    public var autoDetectTitle: String {
        guard let snippet else { return UIStrings.autoDetect }
        return UIStrings.autoDetected(LanguageDetector.detect(snippet.code))
    }
}
