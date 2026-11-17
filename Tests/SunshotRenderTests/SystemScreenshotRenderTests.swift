import CoreGraphics
import Foundation
import ImageIO
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

/// PNG bytes carrying the EXIF comment macOS writes into its screenshots (or another comment).
func screenshotPNG(_ image: CGImage, comment: String? = ImageLoader.systemScreenshotComment) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let comment { properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: comment] }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

@Suite("macOS screenshots and annotations over the backdrop")
struct SystemScreenshotRenderTests {
    private static let red = RGBAColor(rgb: 0xF2453D)

    @Test("[S16-AC10] macOS screenshots are recognised by their EXIF comment and get frame None, in one step")
    func systemScreenshotFrame() throws {
        let image = try Fixtures.solid(width: 120, height: 80)
        #expect(ImageLoader.isSystemScreenshot(try screenshotPNG(image)))
        #expect(!ImageLoader.isSystemScreenshot(try screenshotPNG(image, comment: nil)))
        #expect(!ImageLoader.isSystemScreenshot(try screenshotPNG(image, comment: "Holiday")))
        #expect(!ImageLoader.isSystemScreenshot(Data()))

        var project = Project.plain()
        project.frame.kind = .macWindow
        var session = EditorSession(document: EditorDocument(project: project))
        session.setContent(image, plainFrame: true)
        #expect(session.project.frame.kind == .none)
        session.undo()
        #expect(session.project.frame.kind == .macWindow && !session.hasContent)
        _ = session.addScreenshot(image, plainFrame: true)
        #expect(session.project.frame.kind == .none)

        // The quick-style render of a macOS screenshot has no chrome: the canvas is the content plus padding.
        let style = QuickStyle(project: project)
        let framed = try QuickStyleRenderer.render(image, style: style)
        let plain = try QuickStyleRenderer.render(image, style: style, plainFrame: true)
        #expect(plain.height < framed.height)
        #expect(plain.width == 120 + Int(project.padding) * 2)
    }

    @Test("[S16-AC12] annotations reach over the backdrop, on top of the content's effects")
    func annotationsOverBackdrop() throws {
        var project = Project.plain(padding: 40)
        let arrowOut = Annotation(
            kind: .rectangle, points: [AnnotationPoint(x: -30, y: -30), AnnotationPoint(x: -10, y: -10)],
            color: Self.red, filled: true)
        project.annotations = AnnotationLayer(items: [arrowOut])
        let content = try Fixtures.solid(width: 200, height: 120, red: 1, green: 1, blue: 1)
        let free = try PixelBuffer(try Renderer.render(project: project, content: content))
        // Content (x, y) is canvas (x + 40, y + 40): (-20, -20) lies on the backdrop.
        #expect(free.pixel(x: 20, y: 20) == [242, 69, 61, 255])

        // A device mockup keeps annotations on its screen.
        project.frame.device = DeviceSelection(model: "phone")
        #expect(!Renderer.drawsAnnotationsOnCanvas(project: project, collage: nil))
        project.frame.device = nil
        project.placement.transform.rotation = 10
        #expect(!Renderer.drawsAnnotationsOnCanvas(project: project, collage: nil))
    }
}
