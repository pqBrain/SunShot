import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Renderer")
struct RendererTests {
    @Test("[S0] output size equals layout canvas size times scale", arguments: [1.0, 2.0, 3.0])
    func outputSize(scale: Double) throws {
        let content = try SampleContent.image(width: 400, height: 300)
        let project = Project(canvas: .auto, padding: 40)
        let image = try Renderer.render(project: project, content: content, scale: scale)
        #expect(image.width == Int(480 * scale))
        #expect(image.height == Int(380 * scale))
    }

    @Test("[S0] exact canvas exports exact pixel size")
    func exactCanvas() throws {
        let project = Project(canvas: .exact(PixelSize(width: 1290, height: 2796)))
        let image = try Renderer.render(project: project, content: SampleContent.image())
        #expect((image.width, image.height) == (1290, 2796))
    }

    @Test("[S0] backdrop colour fills the padding and content is not mirrored")
    func pixelsAreWhereExpected() throws {
        let project = Project(backdrop: .solid(.black), padding: 64)
        let pixels = try PixelBuffer(Renderer.render(project: project, content: SampleContent.image()))
        #expect(pixels.pixel(x: 2, y: 2) == [0, 0, 0, 255])
        // Sample content has its dark title strip at the TOP (top-left origin).
        let titleStrip = pixels.pixel(x: pixels.width / 2, y: 64 + 10)
        let body = pixels.pixel(x: pixels.width / 2, y: pixels.height - 64 - 10)
        #expect(titleStrip[0] < 80)
        #expect(body[0] > 240)
    }

    @Test("[S0] transparent backdrop leaves padding transparent")
    func transparentBackdrop() throws {
        let pixels = try PixelBuffer(
            Renderer.render(project: Project(backdrop: .none), content: SampleContent.image()))
        #expect(pixels.pixel(x: 1, y: 1)[3] == 0)
    }

    @Test("[S0] rendering is deterministic (preview/export parity foundation)")
    func deterministic() throws {
        let content = try SampleContent.image()
        let first = try PixelBuffer(Renderer.render(project: Project(), content: content, scale: 2))
        let second = try PixelBuffer(Renderer.render(project: Project(), content: content, scale: 2))
        #expect(first.bytes == second.bytes)
    }

    @Test("[S0] invalid scale falls back to 1×", arguments: [0.0, -1.0, Double.nan])
    func invalidScale(scale: Double) throws {
        let content = try SampleContent.image(width: 100, height: 100)
        let image = try Renderer.render(project: Project(padding: 0), content: content, scale: scale)
        #expect(image.width == 100)
    }

    @Test("[S0] default project snapshot")
    func defaultSnapshot() throws {
        try assertSnapshot(
            Renderer.render(project: Project(), content: SampleContent.image()), named: "default-project")
    }

    @Test("[S0] PNG round-trip preserves size; garbage data fails to decode")
    func codec() throws {
        let image = try SampleContent.image(width: 64, height: 32)
        let decoded = try ImageCodec.decode(ImageCodec.pngData(image))
        #expect((decoded.width, decoded.height) == (64, 32))
        #expect(throws: ImageCodecError.decodeFailed) { try ImageCodec.decode(Data("nope".utf8)) }
    }
}
