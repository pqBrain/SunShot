import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Redaction")
struct RedactionTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    /// White content with one-pixel red "secret" lines every 6 px, optionally translucent.
    private func secret(alpha: CGFloat = 1) throws -> CGImage {
        try Fixtures.draw(width: 300, height: 200) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: alpha))
            for y in stride(from: 0, to: 200, by: 6) { context.fill(CGRect(x: 0, y: y, width: 300, height: 1)) }
            for x in stride(from: 3, to: 300, by: 11) { context.fill(CGRect(x: x, y: 0, width: 1, height: 200)) }
        }
    }

    private func export(_ redaction: Annotation, content: CGImage, scale: Double) throws -> CGImage {
        var project = Project.plain(padding: 20)
        project.annotations.add(redaction)
        return try Renderer.render(project: project, content: content, scale: scale)
    }

    /// Pixels of content rect (x0…x1, y0…y1) in the export, inset by one pixel to skip anti-aliased edges.
    private func region(
        _ pixels: PixelBuffer, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, scale: Double
    ) -> [[UInt8]] {
        var result: [[UInt8]] = []
        for y in Int(Double(y0 + 20) * scale) + 1..<Int(Double(y1 + 20) * scale) - 1 {
            for x in Int(Double(x0 + 20) * scale) + 1..<Int(Double(x1 + 20) * scale) - 1 {
                result.append(pixels.pixel(x: x, y: y))
            }
        }
        return result
    }

    @Test("[S9-AC13] pixelate and blur leave no original detail in the export, at 1× and 2×")
    func destroysDetail() throws {
        let content = try secret()
        for mode in RedactionMode.allCases {
            let redaction = Annotation(kind: .redact, points: [point(40, 40), point(200, 160)], redaction: mode)
            for scale in [1.0, 2.0] {
                let pixels = try PixelBuffer(try export(redaction, content: content, scale: scale))
                let inside = region(pixels, 40, 40, 200, 160, scale: scale)
                let pureRed = inside.filter { $0[0] > 200 && $0[1] < 90 }
                let pureWhite = inside.filter { $0[1] > 245 }
                #expect(pureRed.isEmpty, "\(mode) @\(scale)×: \(pureRed.count) red-line pixels survived")
                #expect(pureWhite.isEmpty, "\(mode) @\(scale)×: \(pureWhite.count) untouched white pixels")
                if scale == 1 {
                    // Outside the region the content is untouched: content (212, 100) is on a red line.
                    #expect(pixels.pixel(x: 232, y: 120) == [255, 0, 0, 255])
                }
            }
        }
    }

    @Test("[S9-AC13] pixelate output is made of flat blocks of at least 8 content pixels")
    func blocks() throws {
        let redaction = Annotation(kind: .redact, points: [point(0, 0), point(160, 160)], lineWidth: 2)
        #expect(RedactionRenderer.blockSize(for: redaction) == 8)
        var blur = redaction
        blur.redaction = .blur
        #expect(RedactionRenderer.blockSize(for: blur) == 16)
        let pixels = try PixelBuffer(try export(redaction, content: try secret(), scale: 1))
        // The first 8×8 block starts at canvas (20, 20); all its pixels are one colour.
        let block = Set((20..<28).flatMap { y in (20..<28).map { pixels.pixel(x: $0, y: y) } })
        #expect(block.count == 1)
    }

    @Test("[S9-AC13] translucent content: the original never shows through the redaction")
    func translucentContent() throws {
        let content = try secret(alpha: 0.5)
        let redaction = Annotation(kind: .redact, points: [point(40, 40), point(200, 160)])
        var project = Project.plain(backdrop: .none, padding: 20)
        project.annotations.add(redaction)
        let pixels = try PixelBuffer(try Renderer.render(project: project, content: content))
        let inside = region(pixels, 40, 40, 200, 160, scale: 1)
        // Original red-line pixels are (128, 0, 0, 128) premultiplied; averages always carry some white.
        #expect(inside.allSatisfy { $0[1] > 30 })
    }

    @Test("[S9-AC13] rotated and off-content redactions are clipped to the content")
    func rotatedAndOutside() throws {
        let content = try secret()
        let rotated = Annotation(kind: .redact, points: [point(100, 60), point(200, 140)], rotation: 45)
        let pixels = try PixelBuffer(try export(rotated, content: content, scale: 1))
        let center = pixels.pixel(x: 170, y: 120)
        #expect(!(center[0] > 200 && center[1] < 90))
        let outside = Annotation(kind: .redact, points: [point(400, 400), point(500, 500)])
        let untouched = try export(outside, content: content, scale: 1)
        let plain = try Renderer.render(project: .plain(padding: 20), content: content)
        #expect(try ImageCodec.pngData(untouched) == ImageCodec.pngData(plain))
        #expect(RedactionRenderer.apply(AnnotationLayer(), to: content) === content)
    }
}
