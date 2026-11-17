import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// The code editor under the preview (snippet documents only). Plain monospaced text; colours show in the preview.
struct CodeEditorPanel: View {
    let model: EditorModel

    var body: some View {
        let code = model.snippet?.code ?? ""
        CodeTextView(text: code) { model.setCode($0) }
            .overlay(alignment: .topLeading) {
                if code.isEmpty {
                    Text(UIStrings.codePlaceholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .padding(.leading, 17)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 210)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding([.leading, .trailing, .bottom], 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(UIStrings.codeEditorAccessibility)
    }
}

/// `NSTextView` with every "smart" substitution off (code must stay exactly as typed) and its own undo off, so
/// ⌘Z goes to the document's undo stack where typing is coalesced.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.isRichText = false
            textView.allowsUndo = false
            textView.drawsBackground = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.textContainerInset = NSSize(width: 12, height: 12)
            textView.setAccessibilityLabel(UIStrings.codeEditorAccessibility)
            textView.string = text
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        // Only push text that changed elsewhere (undo, new snippet), so typing keeps the cursor where it is.
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}
