import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Code snippet editing")
struct SnippetEditingTests {
    private func snippetSession() -> EditorSession {
        var session = EditorSession()
        session.newCodeSnippet()
        return session
    }

    @Test("[S11-AC1] New Code Snippet on an empty document is one undo step; undo empties it again")
    func newOnEmpty() throws {
        var session = EditorSession()
        session.newCodeSnippet()
        #expect(session.snippet == CodeSnippet())
        #expect(session.hasContent)
        #expect(session.history.undoNames == [EditorSession.newSnippetActionName])
        #expect(session.canvasSize != nil)
        #expect(try session.render() != nil)
        session.undo()
        #expect(session.document == EditorDocument())
        #expect(!session.hasContent)
    }

    @Test("[S11-AC1] New Code Snippet replaces an image, keeps the style; undo restores the image")
    func newOverImage() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 120, height: 80))
        session.setCornerStyle(.round)
        let before = session.document
        session.newCodeSnippet()
        #expect(session.document.content == nil)
        #expect(session.snippet != nil)
        #expect(session.project.border.style == .round)
        session.undo()
        #expect(session.document == before)
    }

    @Test("[S11-AC17] importing an image replaces the snippet; Clear Content removes it")
    func imageReplacesSnippet() throws {
        var session = snippetSession()
        session.setContent(try SampleContent.image(width: 50, height: 40))
        #expect(session.snippet == nil)
        #expect(session.history.undoActionName == EditorSession.replaceActionName)
        session.undo()
        #expect(session.snippet != nil)
        session.clearContent()
        #expect(session.snippet == nil && !session.hasContent)
        #expect(session.history.undoActionName == EditorSession.clearActionName)
    }

    @Test("[S11-AC17] snippet canvas size and export follow the snippet's size")
    func exportSnippet() throws {
        var session = snippetSession()
        let size = try #require(session.document.contentPixelSize)
        let pad = Int(session.project.padding) * 2
        #expect(session.canvasSize == PixelSize(width: size.width + pad, height: size.height + pad))
        let plan = try #require(session.exportPlan)
        #expect(plan.width == (size.width + pad) * 2)
        let png = try session.exportImageData()
        let decoded = try ImageCodec.decode(png)
        #expect((decoded.width, decoded.height) == (plan.width, plan.height))
        session.setCodeFontSize(30)
        #expect(try #require(session.canvasSize).width > size.width + pad)
    }

    @Test("[S11-AC15] each snippet edit is one named step; same value records nothing; undo restores")
    func namedSteps() {
        var session = snippetSession()
        let edits: [(String, (inout EditorSession) -> Void)] = [
            (EditorSession.languageActionName, { $0.setLanguage(.python) }),
            (EditorSession.codeThemeActionName, { $0.setCodeTheme("ember") }),
            (EditorSession.lineNumbersActionName, { $0.setShowLineNumbers(false) }),
            (EditorSession.highlightedLinesActionName, { $0.setHighlightedLines([1, 2]) }),
            (EditorSession.snippetTitleActionName, { $0.setSnippetTitle("hello.py") }),
            (EditorSession.codeFontSizeActionName, { $0.setCodeFontSize(20) }),
            (EditorSession.codePaddingActionName, { $0.setCodePadding(12) }),
            (EditorSession.typingActionName, { $0.setCode("print(1)") }),
        ]
        for (name, edit) in edits {
            let before = session.snippet
            let count = session.history.undoCount
            edit(&session)
            #expect(session.history.undoActionName == name)
            #expect(session.history.undoCount == count + 1)
            edit(&session)
            #expect(session.history.undoCount == count + 1, "\(name) repeated should record nothing")
            session.undo()
            #expect(session.snippet == before)
            session.redo()
        }
        let snippet = session.snippet
        #expect(snippet?.language == .python && snippet?.themeID == "ember" && snippet?.fontSize == 20)
    }

    @Test("[S11-AC15] typed highlighted lines: valid text applies, invalid text changes nothing")
    func typedLines() {
        var session = snippetSession()
        let valid = session.setHighlightedLines(text: "2, 4-6")
        #expect(valid)
        #expect(session.snippet?.highlightedLines == [2, 4, 5, 6])
        let count = session.history.undoCount
        let invalid = session.setHighlightedLines(text: "abc")
        #expect(!invalid)
        #expect(session.history.undoCount == count)
        let cleared = session.setHighlightedLines(text: "")
        #expect(cleared)
        #expect(session.snippet?.highlightedLines == [])
    }

    @Test("[S11-AC15] Reset Code Style keeps code, language, title and lines")
    func resetStyle() {
        var session = snippetSession()
        session.setCode("x = 1")
        session.setLanguage(.python)
        session.setSnippetTitle("t")
        session.setHighlightedLines([1])
        session.setCodeTheme("midnight")
        session.setCodeFontSize(30)
        session.setShowLineNumbers(false)
        session.resetCodeStyle()
        #expect(session.history.undoActionName == EditorSession.resetCodeStyleActionName)
        #expect(
            session.snippet
                == CodeSnippet(code: "x = 1", language: .python, highlightedLines: [1], title: "t"))
        let count = session.history.undoCount
        session.resetCodeStyle()
        #expect(session.history.undoCount == count)
    }

    @Test("[S11-AC16] keystrokes inside a gesture become one Typing step")
    func typingGesture() {
        var session = snippetSession()
        let original = session.snippet?.code
        session.beginGesture()
        for text in ["l", "le", "let", "let x"] { session.setCode(text) }
        session.endGesture(EditorSession.typingActionName)
        #expect(session.history.undoNames == [EditorSession.newSnippetActionName, EditorSession.typingActionName])
        session.undo()
        #expect(session.snippet?.code == original)
    }

    @Test("[S11-AC15] snippet edits on an image document do nothing")
    func imageDocumentIgnoresSnippetEdits() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 10, height: 10))
        let count = session.history.undoCount
        session.setCode("x")
        session.setCodeTheme("ember")
        #expect(session.history.undoCount == count && session.snippet == nil)
    }
}
