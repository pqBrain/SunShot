import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

@Suite("Default canvas")
struct DefaultCanvasTests {
    private let backdrop: [UInt8] = [237, 237, 242, 255]

    @Test("[S1-AC6] 1000×600 content → 1128×728 canvas, #EDEDF2 backdrop, content at (64, 64) unscaled")
    func defaultComposition() throws {
        let content = try SampleContent.image(width: 1000, height: 600)
        var session = EditorSession()
        session.setContent(content)
        let image = try #require(try session.render())
        #expect((image.width, image.height) == (1128, 728))
        #expect(SunshotDefaults.backdropColor.hexString.uppercased().hasPrefix("#EDEDF2"))

        let pixels = try PixelBuffer(image)
        #expect(pixels.pixel(x: 0, y: 0) == backdrop)
        #expect(pixels.pixel(x: 63, y: 63) == backdrop)
        #expect(pixels.pixel(x: 1127, y: 727) == backdrop)
        // Content pixels map 1:1 (no scaling): compare against the source.
        let source = try PixelBuffer(content)
        for (x, y) in [(0, 0), (500, 30), (999, 599), (10, 300)] {
            #expect(pixels.pixel(x: 64 + x, y: 64 + y) == source.pixel(x: x, y: y))
        }
        try assertSnapshot(image, named: "s1-default-1000x600")
    }

    @Test("[S1-AC8] transparent content shows the backdrop; 50 % alpha blends 50/50; output is opaque")
    func transparency() throws {
        let content = try Fixtures.draw(width: 200, height: 100) { context in
            // Left half: fully transparent (untouched). Right half: pure blue at 50 % alpha.
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.5))
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        var session = EditorSession()
        session.setContent(try ImageLoader.load(Fixtures.encode(content, as: .png)))
        let image = try #require(try session.render())
        let pixels = try PixelBuffer(image)

        #expect(pixels.pixel(x: 64 + 50, y: 64 + 50) == backdrop)
        let blended = pixels.pixel(x: 64 + 150, y: 64 + 50)
        for (actual, expected) in zip(blended, [119, 119, 249, 255]) {
            #expect(abs(Int(actual) - expected) <= 1)
        }
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast)
        #expect(stride(from: 3, to: pixels.bytes.count, by: 4).allSatisfy { pixels.bytes[$0] == 255 })
        try assertSnapshot(image, named: "s1-transparent-content")
    }
}
