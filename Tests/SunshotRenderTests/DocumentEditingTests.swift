import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Start Over (session)")
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

}

@Suite("S7 × S11 documents")
struct SnippetDocumentTests {
    @Test("[S7-AC1] a code-snippet document saves and reopens with its snippet")
    func snippetRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Snippet.sunshot")
        let document = EditorDocument(snippet: CodeSnippet(code: "let x = 1"))
        try DocumentPackage.write(document, to: url)
        let loaded = try DocumentPackage.read(from: url).document
        #expect(loaded.snippet == document.snippet)
        #expect(loaded.content == nil)
    }
}
