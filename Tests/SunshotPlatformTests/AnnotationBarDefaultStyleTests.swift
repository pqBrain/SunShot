import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Always-visible annotation bar and Set as Default", .serialized)
struct AnnotationBarDefaultStyleTests {
    @Test("[S16-AC8] the annotation bar shows for screenshots and picking a tool enters Annotate mode")
    func annotationBar() async throws {
        let model = EditorModel()
        #expect(!model.showsAnnotationBar, "no content, no bar")
        await model.importData(try ImageCodec.pngData(try TestImages.solid(width: 120, height: 80)))
        #expect(model.showsAnnotationBar && model.isAnnotationBarEnabled && !model.annotate.isActive)

        model.pickAnnotationTool(.arrow)
        #expect(model.annotate.isActive && model.annotate.tool == .arrow)
        model.pickAnnotationTool(.sticker)
        #expect(model.annotate.showsStickerPicker && model.annotate.tool == .arrow)
        model.setAnnotateMode(false)
        #expect(model.showsAnnotationBar && !model.annotate.isActive)

        // Animate mode has its own timeline; code snippets can't be annotated.
        model.setAnimateMode(true)
        #expect(!model.showsAnnotationBar)
        model.setAnimateMode(false)
        await model.setContentKind(.code).value
        #expect(!model.showsAnnotationBar)
        await model.setContentKind(.screenshot).value
        #expect(model.showsAnnotationBar)

        // Content that can't be annotated yet (a device mockup) keeps the bar, disabled.
        await model.setDevice("phone").value
        #expect(model.showsAnnotationBar && !model.isAnnotationBarEnabled)
        model.pickAnnotationTool(.pen)
        #expect(!model.annotate.isActive)
    }

    @Test("[S16-AC9] Set as Default saves the open document's style and shows as done until it changes")
    func setAsDefault() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        controller.model.session.setContent(try TestImages.solid(width: 80, height: 60))
        #expect(!controller.isCurrentStyleDefault)
        controller.model.perform { $0.setPadding(90) }
        controller.saveQuickStyle()
        #expect(controller.isCurrentStyleDefault)
        #expect(controller.effectiveQuickStyle.project.padding == 90)
        // Annotations are per image, not style: they don't make the document differ from the default.
        controller.model.perform {
            $0.commitText("Hi", at: AnnotationPoint(x: 10, y: 10), id: nil, style: AnnotationStyle())
        }
        #expect(controller.isCurrentStyleDefault)
        controller.model.perform { $0.setPadding(20) }
        #expect(!controller.isCurrentStyleDefault)
    }
}
