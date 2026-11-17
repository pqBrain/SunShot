import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Quick-capture styling and Screenshot ⇄ Code")
struct QuickStyleRenderTests {
    @Test("[S16-AC2] a styled capture is the default style's render of it, through the one render function")
    func styledRender() throws {
        let capture = try Fixtures.solid(width: 200, height: 120)
        var project = Project()
        project.padding = 40
        let style = QuickStyle(project: project)
        let output = try QuickStyleRenderer.render(capture, style: style)
        let document = QuickStyleRenderer.document(for: capture, style: style)
        let expected = try #require(try Renderer.render(document: document, scale: 1))
        #expect(output.width == expected.width && output.height == expected.height)
        #expect(output.width > capture.width && output.height > capture.height)
        #expect(document.project.padding == 40)
        #expect(try ImageCodec.decode(try QuickStyleRenderer.pngData(capture, style: style)).width == output.width)
        // No saved style: the plain new document's look.
        let plain = try QuickStyleRenderer.render(capture, style: nil)
        #expect(plain.width >= capture.width)
    }

    @Test("[S16-AC6] switching to Code and back restores the image, crop and annotations; each switch undoes")
    func switchSides() throws {
        var session = EditorSession()
        session.setContent(try Fixtures.solid(width: 300, height: 200))
        session.history.apply("Annotate") {
            $0.project.annotationLayer = AnnotationLayer(stepFormat: .letters)
            $0.crop = CropRect(x: 0, y: 0, width: 100, height: 100)
        }
        let before = session.document
        let stash = try #require(session.imageStash)
        session.showCode(CodeSnippet(code: "let x = 1"))
        #expect(session.document.content == nil && session.document.crop == nil)
        #expect(session.document.project.annotationLayer == nil)
        #expect(session.snippet?.code == "let x = 1")
        #expect(session.imageStash == nil)
        session.showScreenshot(stash)
        #expect(session.document == before)
        #expect(
            session.history.undoNames.suffix(2) == [
                EditorSession.showCodeActionName, EditorSession.showScreenshotActionName,
            ])
        session.undo()
        #expect(session.snippet != nil)
        // With nothing to come back to, Screenshot is the empty "drop an image" state.
        session.showScreenshot(nil)
        #expect(!session.hasContent)
    }
}
