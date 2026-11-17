public import SunshotCore
import SunshotRender

/// S16: the two sides of a document.
public enum ContentKind: String, CaseIterable, Sendable {
    case screenshot, code
}

/// S11: code-snippet documents. Discrete edits go through `perform`; typing and the title field stream through
/// `performContinuous`, so a run of keystrokes is one undo step.
extension EditorModel {
    /// A typing run closes (becomes one "Typing" undo step) after this long without a keystroke.
    public static let typingIdle: Duration = .seconds(1)

    public var snippet: CodeSnippet? { session.snippet }
    public var isSnippet: Bool { session.snippet != nil }

    /// Replaces the content with a new snippet (one undo step "New Code Snippet"). S16: an image is kept aside, so
    /// switching back to Screenshot shows it again.
    @discardableResult
    public func newCodeSnippet() -> Task<Void, Never> {
        setAnnotateMode(false)
        if let stash = session.imageStash { stashedImage = stash }
        return perform { $0.newCodeSnippet() }
    }

    // MARK: S16 Screenshot ⇄ Code

    /// Which side of the document is shown; the toolbar's Screenshot / Code switch.
    public var contentKind: ContentKind { isSnippet ? .code : .screenshot }

    /// Switches sides, keeping the other side to come back to (one undo step). Switching to Code without a snippet
    /// starts an empty one; switching to Screenshot without an image shows the empty "drop an image" state.
    @discardableResult
    public func setContentKind(_ kind: ContentKind) -> Task<Void, Never> {
        guard kind != contentKind else { return Task {} }
        setAnnotateMode(false)
        switch kind {
        case .code:
            if let stash = session.imageStash { stashedImage = stash }
            let snippet = stashedSnippet ?? CodeSnippet()
            return perform { $0.showCode(snippet) }
        case .screenshot:
            stashedSnippet = snippet
            let stash = stashedImage
            return perform { $0.showScreenshot(stash) }
        }
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
