import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("S17 studio polish", .serialized)
struct StudioPolishTests {
    @Test(
        "[S17-AC3] the Annotate button hides and shows the annotation bar; shown by default; Annotate mode brings it back"
    )
    func annotationBarToggle() async throws {
        let model = EditorModel()
        #expect(!model.canToggleAnnotationBar, "nothing to annotate yet")
        await model.importData(try ImageCodec.pngData(try TestImages.solid(width: 120, height: 80)))
        #expect(model.showsAnnotationBar && model.canToggleAnnotationBar)
        #expect(model.annotationBarToggleTitle == UIStrings.hideAnnotationBar)

        model.pickAnnotationTool(.arrow)
        #expect(model.annotate.isActive)
        model.toggleAnnotationBar()
        #expect(!model.showsAnnotationBar && !model.annotate.isActive, "hiding the bar leaves Annotate mode")
        #expect(model.annotationBarToggleTitle == UIStrings.showAnnotationBar)

        model.toggleAnnotationBar()
        #expect(model.showsAnnotationBar && !model.annotate.isActive, "showing it doesn't enter Annotate mode")

        model.toggleAnnotationBar()
        model.setAnnotateMode(true)  // ⇧⌘A or a capture opened in Annotate mode
        #expect(model.showsAnnotationBar && model.annotate.isActive)

        // Not saved: a new editor (relaunch) shows the bar again.
        model.toggleAnnotationBar()
        #expect(!EditorModel().hidesAnnotationBar)

        // Code snippets and Animate mode have no bar to toggle.
        await model.setContentKind(.code).value
        #expect(!model.canToggleAnnotationBar && !model.showsAnnotationBar)
    }

    @Test("[S17-AC4] messages stack above the bottom bar whenever it shows")
    func noticeAboveBottomBar() async throws {
        let model = EditorModel()
        #expect(!model.showsBottomBar)
        await model.importData(try ImageCodec.pngData(try TestImages.solid(width: 120, height: 80)))
        #expect(model.showsBottomBar, "Position / Crop bar")
        model.setAnimateMode(true)
        #expect(model.showsBottomBar, "Animate timeline")
        model.setAnimateMode(false)
        model.setAnnotateMode(true)
        #expect(!model.showsBottomBar, "Annotate mode has no bottom bar")
    }

    @Test("[S17-AC1] a document saved with a theme still opens with its style")
    func themedDocumentsStillOpen() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        await controller.model.importData(try TestImages.png())
        await controller.model.perform { $0.setFrameKind(.macWindow) }.value
        let url = fixture.folder.file("Themed.sunshot")
        #expect(await controller.saveAs(to: url))
        let styled = controller.model.project
        // Give it the `theme` record documents saved before S17 carry (the theme library is gone).
        let manifestURL = url.appendingPathComponent(DocumentManifest.fileName)
        var manifest = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["theme"] = [
            "schemaVersion": 1, "id": "6F1E0C1A-0000-4000-8000-000000000001", "name": "Ocean",
            "style": ["border": ["radius": 40, "style": "round"]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        let reopened = try ControllerFixture()
        defer { reopened.cleanUp() }
        #expect(await reopened.controller.openDocument(at: url))
        #expect(reopened.controller.model.project == styled)
        #expect(SidebarPane.allCases == [.layouts, .templates])
    }
}

@MainActor
@Suite("S17 code layouts and Clear")
struct StudioPolishCodeTests {
    @Test("[S17-AC7] code snippets get layout thumbnails, refreshed when the code changes")
    func snippetLayoutThumbnails() async throws {
        var document = EditorDocument()
        document.snippet = CodeSnippet(code: "let hour = 6")
        let presets = LayoutLibrary.shared.presets
        try #require(!presets.isEmpty)
        let thumbnails = try LayoutThumbnails.render(document: document, presets: presets)
        #expect(thumbnails.count == presets.count)
        let preset = try #require(presets.first)
        var variant = document
        variant.project.placement = ContentPlacement(transform: preset.transform, layoutPresetID: preset.id)
        let scale = try #require(LayoutThumbnails.scale(for: document, maxSide: LayoutThumbnails.defaultMaxSide))
        let direct = try #require(try Renderer.render(document: variant, scale: scale))
        let thumbnail = try #require(thumbnails[preset.id])
        #expect(try PixelBufferBytes.of(thumbnail) == PixelBufferBytes.of(direct))

        let key = try #require(LayoutThumbnailKey(document: document, maxSide: 200))
        var edited = document
        edited.snippet?.code = "let hour = 7"
        #expect(LayoutThumbnailKey(document: edited, maxSide: 200) != key)
    }

    @Test("[S17-AC8] the annotation bar's clear button reads \"Clear\"; menus and VoiceOver keep the full name")
    func shortClear() {
        #expect(UIStrings.clearAnnotationsShort == "Clear")
        #expect(UIStrings.clearAnnotations == "Clear Annotations")
    }
}
