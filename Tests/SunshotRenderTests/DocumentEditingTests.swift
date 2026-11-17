import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Start Over and themes (session)")
struct DocumentEditingTests {
    @Test("[S7-AC7] [S7-AC8] Start Over resets content and style as one undo step; undo restores everything")
    func startOver() throws {
        var session = try DocumentFixtures.styledSession(contentSize: 60)
        let before = session.document
        let pixels = try session.render().map(ImageCodec.pngData)
        let undoCount = session.history.undoCount
        #expect(session.canStartOver)
        session.startOver()
        #expect(session.document == EditorSession.defaultDocument)
        #expect(session.history.undoActionName == "Start Over" && session.history.undoCount == undoCount + 1)
        session.undo()
        #expect(session.document == before)
        #expect(try session.render().map(ImageCodec.pngData) == pixels)
    }

    @Test("[S7-AC8] Start Over on a default document is a no-op with no undo entry")
    func startOverNoOp() {
        var session = EditorSession()
        #expect(!session.canStartOver)
        session.startOver()
        #expect(!session.history.canUndo)
    }

    @Test("[S7-AC10] Apply Theme is one undo step that keeps content, canvas and export options")
    func applyTheme() throws {
        var source = try DocumentFixtures.styledSession(contentSize: 60)
        source.setBackdropColor(.black)
        let paper = try Theme.extract(from: source.project, name: "Paper")
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 40, height: 20))
        session.setCanvas(.exact(PixelSize(width: 500, height: 400)))
        session.setExportFormat(.heic)
        let before = session.document
        try session.applyTheme(paper)
        #expect(session.history.undoActionName == "Apply Theme Paper")
        #expect(session.project.border == source.project.border && session.project.shadow == source.project.shadow)
        #expect(session.project.backdrop == .solid(.black))
        #expect(session.project.canvas == before.project.canvas && session.project.export == before.project.export)
        #expect(session.document.content == before.content && session.document.theme == paper)
        session.undo()
        #expect(session.document == before && session.document.theme == nil)
        // Applying the same theme twice records one step only.
        try session.applyTheme(paper)
        try session.applyTheme(paper)
        #expect(session.history.undoNames.filter { $0 == "Apply Theme Paper" }.count == 1)
    }

    @Test("[S7-AC9] Save Theme marks the theme as applied (undoable)")
    func markSaved() throws {
        var session = EditorSession()
        let theme = try Theme.extract(from: session.project, name: "Ocean")
        session.markThemeSaved(theme)
        #expect(session.document.theme == theme && session.history.undoActionName == "Save Theme")
        session.undo()
        #expect(session.document.theme == nil)
    }
}
