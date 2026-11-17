import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Device and template editing")
struct DeviceEditingTests {
    private static func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 360, height: 780))
        return session
    }

    @Test("[S12-AC12] device edits are single named undo steps; no-ops record nothing")
    func deviceUndo() throws {
        var session = try Self.session()
        session.setFrameKind(.macWindow)
        var count = session.history.undoCount
        func expectStep(_ name: String) {
            #expect(session.history.undoCount == count + 1 && session.history.undoActionName == name)
            count = session.history.undoCount
        }
        session.setDevice("phone")
        expectStep("Change Device")
        #expect(session.device == DeviceSelection(model: "phone") && session.project.frame.kind == .none)
        session.setDevice("phone")
        #expect(session.history.undoCount == count)
        session.setDeviceFinish("sand")
        expectStep("Change Device Finish")
        session.setDeviceFinish("gold")
        session.setDeviceLandscape(true)
        expectStep("Change Device Orientation")
        session.setDeviceArrangement("trio")
        expectStep("Change Device Layout")
        session.setDeviceArrangement("nope")
        #expect(session.history.undoCount == count)
        // Another model keeps the finish, the orientation (if it turns) and a compatible layout.
        session.setDevice("tablet")
        expectStep("Change Device")
        #expect(
            session.device == DeviceSelection(model: "tablet", finish: "sand", landscape: true, arrangement: "trio"))
        session.setDevice("laptop")
        #expect(session.device?.landscape == false)
        session.setDeviceLandscape(true)
        #expect(session.device?.landscape == false)
        session.setDevice("unknown")
        #expect(session.device?.model == "laptop")
        count = session.history.undoCount
        // A fixed combination selects its model; a model it can't show falls back to Single.
        session.setDeviceArrangement("laptop-phone")
        #expect(session.device?.model == "laptop" && session.device?.arrangement == "laptop-phone")
        session.setDeviceArrangement("tablet-phone")
        #expect(session.device?.model == "tablet")
        session.setDevice("phone")
        #expect(session.device?.arrangement == "single")
        session.setDevice(nil)
        #expect(session.history.undoActionName == "Remove Device" && session.device == nil)
        session.undo()
        #expect(session.device?.model == "phone")
        // A frame kind removes the device.
        session.setFrameKind(.card)
        #expect(session.device == nil && session.project.frame.kind == .card)
        session.undo()
        #expect(session.device?.model == "phone" && session.project.frame.kind == .none)
        session.setDeviceLandscape(false)
        session.applyDeviceSuggestion(
            try #require(DeviceSuggestion.suggest(for: PixelSize(width: 2752, height: 2064))))
        #expect(session.device == DeviceSelection(model: "tablet", finish: "sand", landscape: true))
        #expect(session.history.undoActionName == "Change Device")
    }

    @Test("[S12-AC18] applying a template restyles in one step and keeps content, annotations, title and export")
    func applyTemplate() throws {
        var session = try Self.session()
        session.setFrameTitle("Kept")
        session.addAnnotation(
            Annotation(kind: .pen, points: [AnnotationPoint(x: 1, y: 1), AnnotationPoint(x: 9, y: 9)]))
        session.setExportScale(.k4)
        let theme = try Theme.extract(from: session.project, name: "Mine")
        try session.applyTheme(theme)
        let before = session.document
        let template = try #require(try TemplateCatalog.load().template(matching: "desk-and-pocket"))
        session.applyTemplate(template)
        #expect(session.history.undoActionName == "Apply Template Desk & Pocket")
        let project = session.project
        #expect(project.frame.device == template.project.frame.device && project.canvas == template.project.canvas)
        #expect(project.backdrop == template.project.backdrop && project.padding == template.project.padding)
        #expect(project.frame.title == "Kept" && project.annotations == before.project.annotations)
        #expect(project.export == before.project.export && session.document.content == before.content)
        #expect(session.document.theme == nil)
        let count = session.history.undoCount
        session.applyTemplate(template)
        #expect(session.history.undoCount == count)
        session.undo()
        #expect(session.document == before)
    }

    @Test("[S12-AC19] Start Over and new documents use a template's document")
    func startOverTemplate() throws {
        var session = try Self.session()
        let template = try #require(try TemplateCatalog.load().template(matching: "pocket-spotlight"))
        let start = EditorSession.document(for: template)
        #expect(start.project == template.project && start.content == nil)
        #expect(EditorSession.document(for: nil) == EditorSession.defaultDocument)
        #expect(session.canStartOver(to: start))
        session.startOver(to: start)
        #expect(session.document == start && session.history.undoActionName == "Start Over")
        #expect(!session.canStartOver(to: start) && session.canStartOver)
    }

    @Test("[S12-AC17] gallery previews are the template document rendered by the shared renderer")
    func previews() throws {
        let catalog = try TemplateCatalog.load()
        let session = try Self.session()
        for template in catalog.templates {
            let card = try #require(try TemplateThumbnails.render(template, document: session.document))
            #expect(max(card.width, card.height) == TemplateThumbnails.defaultMaxSide, "\(template.id)")
            let variant = TemplateThumbnails.preview(template, of: session.document)
            #expect(variant.project == EditorSession.project(template, keeping: session.project))
            let canvas = CanvasLayout.compute(contentSize: PixelSize(width: 360, height: 780), project: variant.project)
                .canvasSize
            let scale = Double(TemplateThumbnails.defaultMaxSide) / Double(max(canvas.width, canvas.height))
            let direct = try #require(try Renderer.render(document: variant, scale: scale))
            #expect(try PixelBuffer(card).bytes == PixelBuffer(direct).bytes, "\(template.id)")
        }
        // Empty documents use sample content of the template's recommended size.
        let empty = try #require(try TemplateThumbnails.render(catalog.templates[4], document: EditorDocument()))
        #expect(max(empty.width, empty.height) == TemplateThumbnails.defaultMaxSide)
        // Code snippets preview too.
        var snippet = EditorSession()
        snippet.newCodeSnippet()
        #expect(try TemplateThumbnails.render(catalog.templates[1], document: snippet.document) != nil)
        let tile = try TemplateThumbnails.renderDevice(
            try #require(DeviceCatalog.bundled.model("phone")), finish: "sage")
        #expect(max(tile.width, tile.height) == 96)
    }

    @Test("[S12-AC20] documents save and reopen with their device")
    func packageRoundTrip() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = try Self.session()
        session.setDevice("phone")
        session.setDeviceArrangement("trio")
        let url = folder.file("Device.sunshot")
        try DocumentPackage.write(session.document, to: url)
        let loaded = try DocumentPackage.read(from: url)
        #expect(loaded.document.project.frame.device == session.device)
        #expect(
            try Renderer.render(document: loaded.document).map(ImageCodec.pngData)
                == session.render().map(ImageCodec.pngData))
    }
}
