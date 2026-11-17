import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Code snippet model", .serialized)
struct SnippetModelTests {
    private func snippetModel() async -> EditorModel {
        let model = EditorModel()
        await model.newCodeSnippet().value
        return model
    }

    @Test("[S11-AC1] New Code Snippet from the model shows a preview and is undoable")
    func newSnippet() async throws {
        let model = await snippetModel()
        #expect(model.isSnippet && model.hasContent && model.isInspectorEnabled)
        #expect(model.preview != nil)
        #expect(model.undoTitle == "Undo New Code Snippet")
        await model.undo()
        #expect(!model.hasContent && model.snippet == nil)
    }

    @Test("[S11-AC16] keystrokes less than the idle time apart are one Typing step; another edit closes it")
    func typingRun() async throws {
        let model = await snippetModel()
        let original = model.snippet?.code
        for text in ["l", "le", "let", "let x"] { model.setCode(text, idle: .seconds(60)) }
        #expect(model.hasPendingContinuousEdit)
        #expect(model.snippet?.code == "let x")
        await model.perform { $0.setShowLineNumbers(false) }.value
        #expect(!model.hasPendingContinuousEdit)
        #expect(
            model.session.history.undoNames == [
                EditorSession.newSnippetActionName, EditorSession.typingActionName,
                EditorSession.lineNumbersActionName,
            ])
        await model.undo()
        await model.undo()
        #expect(model.snippet?.code == original)
    }

    @Test("[S11-AC16] a pause closes the typing run; undo closes it too")
    func typingIdle() async throws {
        let model = await snippetModel()
        model.setCode("a", idle: .milliseconds(20))
        model.setCode("ab", idle: .milliseconds(20))
        for _ in 0..<100 where model.hasPendingContinuousEdit { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.hasPendingContinuousEdit && model.undoTitle == "Undo Typing")
        model.setCode("abc", idle: .seconds(60))
        await model.undo()
        #expect(model.snippet?.code == "ab")
        #expect(!model.hasPendingContinuousEdit)
        #expect(EditorModel.typingIdle == .seconds(1))
    }

    @Test("[S11-AC16] the title field is merged like typing; unchanged text records nothing")
    func titleRun() async throws {
        let model = await snippetModel()
        for text in ["m", "ma", "main"] { model.setSnippetTitle(text, idle: .seconds(60)) }
        model.finishContinuousEdit()
        #expect(model.undoTitle == "Undo Change Snippet Title")
        let count = model.session.history.undoCount
        model.setSnippetTitle("main")
        model.setCode(model.snippet?.code ?? "")
        #expect(!model.hasPendingContinuousEdit && model.session.history.undoCount == count)
    }

    @Test("[S11-AC17] snippet documents export with the code template name; images replace the snippet")
    func exportAndReplace() async throws {
        let model = await snippetModel()
        #expect(model.canExport)
        let name = model.suggestedExportName(now: Date(timeIntervalSince1970: 0)) { "abcdef" }
        #expect(name.hasPrefix("code_2x_sunshot_"))
        let png = try await model.pngData()
        #expect(try ImageCodec.decode(png).width == model.exportPlan?.width)
        let preset = try #require(try CanvasPresetCatalog.load().presets.first)
        #expect(model.canvasSize(for: preset) != nil)
        await model.importData(try TestImages.png(), fileName: "a.png")
        #expect(!model.isSnippet && model.hasContent)
        #expect(model.undoTitle == "Undo Replace Image")
        #expect(model.suggestedExportName().hasPrefix("screenshot_"))
    }

    @Test("[S11-AC15] highlighted lines and language labels through the model")
    func inspectorBindings() async throws {
        let model = await snippetModel()
        #expect(model.autoDetectTitle == "Auto-detect (Swift)")
        #expect(model.setHighlightedLines(text: "4-6, 2"))
        #expect(model.highlightedLinesText == "2, 4–6")
        #expect(!model.setHighlightedLines(text: "nope"))
        #expect(model.highlightedLinesText == "2, 4–6")
        let snippet = try #require(model.snippet)
        #expect(UIStrings.languageAccessibility(snippet) == "Language: Auto-detect (Swift)")
        await model.perform { $0.setLanguage(.go) }.value
        #expect(UIStrings.languageAccessibility(try #require(model.snippet)) == "Language: Go")
        #expect(UIStrings.fontSizeAccessibility(15) == "Code font size, 15 pixels")
        #expect(UIStrings.codePaddingAccessibility(28.4) == "Code padding, 28 pixels")
        #expect(UIStrings.highlightedLinesAccessibility("") == "Highlighted lines, none")
        #expect(UIStrings.highlightedLinesAccessibility("2") == "Highlighted lines, 2")
        let empty = EditorModel()
        #expect(empty.autoDetectTitle == "Auto-detect")
        #expect(empty.highlightedLinesText.isEmpty)
    }

    @Test("[S11-AC18] snippet documents show the editor and Code section; image documents show neither")
    func editorPanelAndSection() async throws {
        let model = await snippetModel()
        #expect(model.isSnippet, "the code editor panel and Code section are shown for snippets")
        #expect(UIStrings.codePlaceholder == "Enter some code…" && UIStrings.codeEditorAccessibility == "Code editor")
        let controls = [
            UIStrings.languagePicker, UIStrings.themePicker, UIStrings.lineNumbersToggle,
            UIStrings.highlightedLinesField, UIStrings.titleField, UIStrings.fontSizeSlider,
            UIStrings.codePaddingSlider,
        ]
        #expect(
            controls == ["Language", "Theme", "Line numbers", "Highlighted lines", "Title", "Font size", "Padding"])
        model.setCode("import Foundation\nlet x = 1\n", idle: .zero)
        #expect(model.autoDetectTitle == "Auto-detect (Swift)")
        let snippet = try #require(model.snippet)
        #expect(UIStrings.languageAccessibility(snippet) == "Language: Auto-detect (Swift)")
        #expect(UIStrings.fontSizeAccessibility(14) == "Code font size, 14 pixels")
        #expect(UIStrings.codePaddingAccessibility(32) == "Code padding, 32 pixels")
        #expect(CodeLanguage.allCases.count >= 2)
        await model.importData(try TestImages.png(), fileName: "shot.png")
        #expect(!model.isSnippet && model.snippet == nil, "images hide the editor and the Code section")
    }
}
