import CoreGraphics
import Foundation
import ImageIO
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Canvas size and export")
struct CanvasExportTests {
    private static func session(width: Int = 1000, height: Int = 600) throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: width, height: height))
        return session
    }

    private static func custom(_ session: inout EditorSession, width: String, height: String) -> Bool {
        session.setCustomCanvas(width: width, height: height)
    }

    private static func decoded(_ data: Data) throws -> (image: CGImage, type: String) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image, type)
    }

    @Test("[S4-AC1] a new document is Auto: canvas = content + 64 px on each side")
    func autoDefault() throws {
        let session = try Self.session()
        #expect(session.document.project.canvas == .auto)
        #expect(session.canvasSize == PixelSize(width: 1128, height: 728))
        #expect(session.document.project.export == ExportOptions(format: .png, scale: .x2))
    }

    @Test("[S4-AC5] every store preset exports at exactly pixelW × pixelH, whatever the scale")
    func storeExports() throws {
        var session = try Self.session()
        session.setExportScale(.k6)
        let store = try CanvasPresetCatalog.load().presets.filter { $0.group == .store }
        #expect(!store.isEmpty)
        for preset in store {
            session.selectCanvasPreset(preset)
            let image = try Self.decoded(session.exportImageData()).image
            #expect(PixelSize(width: image.width, height: image.height) == preset.exactSize, "\(preset.id)")
        }
    }

    @Test("[S4-AC5] exact canvases scale border radius and shadow with the content")
    func exactStyled() throws {
        var session = try Self.session(width: 640, height: 400)
        session.setCornerRadius(40)
        session.setShadowIntensity(.high)
        let tile = CanvasPreset(
            id: "t", group: .store, name: "Tile", ratioW: 11, ratioH: 7, pixelW: 440, pixelH: 280)
        session.selectCanvasPreset(tile)
        let image = try #require(try session.render())
        #expect((image.width, image.height) == (440, 280))
        try assertSnapshot(image, named: "s4-exact-preset-styled")
    }

    @Test("[S4-AC6] invalid custom sizes are refused: canvas kept, no undo entry")
    func customRejected() throws {
        var session = try Self.session()
        #expect(Self.custom(&session, width: "800", height: "600"))
        let undoCount = session.history.undoCount
        for (width, height) in [("0", "100"), ("-5", "100"), ("20000", "100"), ("abc", "100")] {
            #expect(!Self.custom(&session, width: width, height: height))
        }
        #expect(session.history.undoCount == undoCount)
        #expect(session.canvasSize == PixelSize(width: 800, height: 600))
        #expect(Self.custom(&session, width: "16384", height: "16384"))
        #expect(Self.custom(&session, width: "1", height: "1"))
        #expect(session.canvasSize == PixelSize(width: 1, height: 1))
    }

    @Test("[S4-AC8] 16:9 → custom 800×600 → Auto: one \"Change Canvas Size\" step each, undo/redo exact")
    func canvasUndo() throws {
        var session = try Self.session()
        let start = session.history.undoCount
        let wide = CanvasPreset(id: "general.widescreen", group: .general, name: "Widescreen", ratioW: 16, ratioH: 9)
        session.selectCanvasPreset(wide)
        #expect(session.canvasSize == PixelSize(width: 1294, height: 728))
        #expect(Self.custom(&session, width: "800", height: "600"))
        session.resetCanvas()
        session.resetCanvas()  // no-op: no extra entry
        #expect(session.history.undoCount == start + 3)
        #expect(session.history.undoNames.suffix(3).allSatisfy { $0 == "Change Canvas Size" })
        session.undo()
        #expect(session.document.project.canvas == .custom(CustomCanvasSize(width: 800, height: 600)))
        session.undo()
        #expect(session.document.project.canvas == .preset(wide))
        session.undo()
        #expect(session.document.project.canvas == .auto)
        session.redo()
        session.redo()
        #expect(session.document.project.canvas == .custom(CustomCanvasSize(width: 800, height: 600)))
        #expect(session.canvasSize == PixelSize(width: 800, height: 600))
    }

    @Test("[S4-AC9] format and scale are stored in the document, undoable; WebP offered only if writable")
    func formatChoice() throws {
        var session = try Self.session()
        session.setExportFormat(.heic)
        session.setExportScale(.k4)
        session.setExportScale(.k4)
        #expect(session.document.project.export == ExportOptions(format: .heic, scale: .k4))
        #expect(session.history.undoNames.suffix(2) == ["Change Export Format", "Change Export Scale"])
        session.undo()
        #expect(session.document.project.export.scale == .x2)

        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        #expect(ImageCodec.writableFormats.contains(.webp) == writable.contains("org.webmproject.webp"))
        #expect(Array(ImageCodec.writableFormats.prefix(3)) == [.png, .jpeg, .heic])
    }

    @Test("[S4-AC10] every writable format decodes with the right size and type; unwritable ones are refused")
    func encodings() throws {
        var session = try Self.session()
        session.setExportScale(.x1)
        for format in ExportFormat.allCases {
            session.setExportFormat(format)
            guard ImageCodec.canWrite(format) else {
                #expect(throws: ExportError.formatUnavailable(format)) { try session.exportImageData() }
                continue
            }
            let (image, type) = try Self.decoded(session.exportImageData())
            #expect((image.width, image.height) == (1128, 728), "\(format)")
            #expect(type == format.typeIdentifier)
        }
    }

    @Test("[S4-AC10] JPEG of a transparent backdrop is flattened onto white, never black")
    func jpegOnWhite() throws {
        var session = try Self.session()
        session.setBackdropKind(.none)
        session.setExportFormat(.jpeg)
        session.setExportScale(.x1)
        #expect(!session.document.project.backdrop.isOpaque)
        let image = try Self.decoded(session.exportImageData()).image
        let corner = try PixelBuffer(image).pixel(x: 2, y: 2)
        #expect(corner.prefix(3).allSatisfy { $0 >= 250 }, "corner \(corner)")
        #expect(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst)
    }

    @Test("[S4-AC11] exported files are 1128×728, 2256×1456, 3840×2478 and 6144×3965")
    func scaleSizes() throws {
        var session = try Self.session()
        let expected: [(ExportScale, Int, Int)] = [
            (.x1, 1128, 728), (.x2, 2256, 1456), (.k4, 3840, 2478), (.k6, 6144, 3965),
        ]
        for (scale, width, height) in expected {
            session.setExportScale(scale)
            #expect(session.exportPlan?.outputSize == PixelSize(width: width, height: height))
            let image = try Self.decoded(session.exportImageData()).image
            #expect((image.width, image.height) == (width, height), "\(scale)")
        }
    }

    @Test("[S4-AC12] 16384² at 2× is refused before rendering; at 6K it exports at 6144²")
    func tooLargeRefused() throws {
        var session = try Self.session(width: 64, height: 64)
        #expect(Self.custom(&session, width: "16384", height: "16384"))
        session.setExportScale(.x2)
        #expect(throws: ExportError.tooLarge(width: 32768, height: 32768)) { try session.exportImageData() }
        #expect(throws: ExportError.tooLarge(width: 32768, height: 32768)) { try session.copyPNGData() }
        session.setExportScale(.k6)
        #expect(session.exportPlan?.outputSize == PixelSize(width: 6144, height: 6144))
        #expect(session.exportPlan?.isTooLarge == false)
    }

    @Test("[S4-AC13] export equals the preview render at 1× and 2× (4K/6K run in the release perf suite)")
    func parity() throws {
        var session = EditorSession()
        session.setContent(try Fixtures.solid(width: 200, height: 120))
        session.setCornerRadius(24)
        session.setShadowIntensity(.high)
        session.setBackdropKind(.gradient)
        for scale in [ExportScale.x1, .x2] {
            session.setExportScale(scale)
            let plan = try #require(session.exportPlan)
            let preview = try #require(try Renderer.render(document: session.document, scale: plan.renderScale))
            #expect(try session.exportImageData() == ImageCodec.pngData(preview), "\(scale)")
        }
    }

    @Test("[S4-AC18] copy is always a PNG at the export scale, even when the format is JPEG")
    func copyIsPNG() throws {
        var session = try Self.session()
        session.setExportFormat(.jpeg)
        session.setExportScale(.k4)
        let (image, type) = try Self.decoded(session.copyPNGData())
        #expect(type == "public.png")
        #expect((image.width, image.height) == (3840, 2478))
    }
}
