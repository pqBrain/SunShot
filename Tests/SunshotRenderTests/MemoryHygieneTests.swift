import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Guards that keep Sunshot light: the undo history weighs the images it holds, and quick styling refuses canvases
/// over the maximum side instead of allocating them.
@Suite("Memory hygiene")
struct MemoryHygieneTests {
    @Test("history resources: content, slots and media, by identity, pixels plus file bytes")
    func historyResources() throws {
        var session = EditorSession()
        let image = try Fixtures.solid(width: 100, height: 50)
        session.setContent(image, data: Data(count: 10))
        let slot = ContentImage(try Fixtures.solid(width: 20, height: 20))
        session.history.apply("Slot") { $0.slots[1] = slot }
        let resources = EditorDocument.historyResources(session.document)
        #expect(resources.count == 2)
        let content = try #require(session.document.content)
        let entry = try #require(resources.first { $0.id == content.id.uuidString })
        #expect(entry.bytes == image.bytesPerRow * image.height + 10)
        // A style change shares the images: the weights don't change.
        session.history.apply("Pad") { $0.project.padding = 12 }
        #expect(EditorDocument.historyResources(session.document).map(\.id) == resources.map(\.id))
    }

    @Test("a quick style whose canvas would pass the maximum side throws tooLarge before rendering")
    func quickStyleTooLarge() throws {
        let wide = try Fixtures.solid(width: SunshotDefaults.maxCanvasSide - 10, height: 4)
        var project = Project()
        project.padding = 200
        #expect(throws: ExportError.self) {
            _ = try QuickStyleRenderer.render(wide, style: QuickStyle(project: project))
        }
    }
}
