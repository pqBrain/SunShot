import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

@Suite("Editor session (single document store)")
struct EditorSessionTests {
    private func image(_ width: Int = 30, _ height: Int = 20, red: CGFloat = 0.2) throws -> CGImage {
        try Fixtures.solid(width: width, height: height, red: red)
    }

    @Test("[S1-AC1] a new session is empty: no content, no canvas, nothing to undo, no render")
    func emptyState() throws {
        let session = EditorSession()
        #expect(!session.hasContent && session.canvasSize == nil)
        #expect(!session.history.canUndo && !session.history.canRedo)
        #expect(try session.render() == nil)
        #expect(throws: RenderError.noContent) { try session.exportPNG() }
    }

    @Test("[S1-AC15] import, replace, clear produce three named undo steps that undo and redo in order")
    func undoRedoSequence() throws {
        var session = EditorSession()
        let first = try image(red: 0.1)
        let second = try image(red: 0.9)
        session.setContent(first)
        let firstID = try #require(session.document.content?.id)
        session.setContent(second)
        let secondID = try #require(session.document.content?.id)
        session.clearContent()

        #expect(session.history.undoNames == ["Import Image", "Replace Image", "Clear Content"])
        session.undo()
        #expect(session.document.content?.id == secondID)
        session.undo()
        #expect(session.document.content?.id == firstID)
        session.undo()
        #expect(session.document.content == nil)
        #expect(!session.history.canUndo)

        session.redo()
        #expect(session.document.content?.id == firstID)
        session.redo()
        #expect(session.document.content?.id == secondID)
        session.redo()
        #expect(session.document.content == nil)
    }

    @Test("[S1-AC15] a new mutation after undo discards the redo stack")
    func newMutationClearsRedo() throws {
        var session = EditorSession()
        session.setContent(try image())
        session.setContent(try image(red: 0.7))
        session.undo()
        #expect(session.history.canRedo)
        session.clearContent()
        #expect(!session.history.canRedo)
    }

    @Test("[S1-AC16] importing over content replaces it without prompting; one undo restores the original")
    func replace() throws {
        var session = EditorSession()
        try session.importImage(data: Fixtures.encode(image(10, 10), as: .png))
        let original = try #require(session.document.content)
        try session.importImage(data: Fixtures.encode(image(50, 40), as: .png))
        #expect(session.document.content?.pixelSize == PixelSize(width: 50, height: 40))
        #expect(session.history.undoActionName == EditorSession.replaceActionName)
        session.undo()
        #expect(session.document.content == original)
    }

    @Test("[S1-AC3] a failed import leaves content and the undo stack untouched")
    func failedImportIsNoOp() throws {
        var session = EditorSession()
        session.setContent(try image())
        let before = session.document
        let undoCount = session.history.undoCount
        #expect(throws: ImageLoadError.self) { try session.importImage(data: Data("nope".utf8)) }
        #expect(session.document == before)
        #expect(session.history.undoCount == undoCount)
    }

    @Test("[S1-AC14] clear returns to the empty state, is undoable and redoable; clearing empty is a no-op")
    func clear() throws {
        var session = EditorSession()
        session.clearContent()
        #expect(session.history.undoCount == 0)
        session.setContent(try image())
        let content = session.document.content
        session.clearContent()
        #expect(!session.hasContent && session.canvasSize == nil)
        #expect(session.history.undoActionName == "Clear Content")
        session.undo()
        #expect(session.document.content == content)
        session.redo()
        #expect(!session.hasContent)
    }

    @Test("[S1-AC13] preview and export go through the same render(document:scale:) and are byte-identical")
    func previewExportParity() throws {
        for content in [try image(1000, 600), try transparentContent()] {
            var session = EditorSession()
            session.setContent(content)
            let preview = try #require(try Renderer.render(document: session.document, scale: 1))
            let exported = try ImageCodec.decode(session.exportPNG(scale: 1))
            #expect(try PixelBuffer(preview).bytes == PixelBuffer(exported).bytes)
        }
    }

    private func transparentContent() throws -> CGImage {
        try Fixtures.draw(width: 640, height: 480) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
        }
    }
}
