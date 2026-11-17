import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Annotation rendering")
struct AnnotationRenderTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    private static let red = RGBAColor(rgb: 0xF2453D)

    /// White content, padding 20, sharp, no shadow: content pixel (x, y) is canvas pixel (x + 20, y + 20).
    private func render(
        _ items: [Annotation], content: CGImage? = nil, stepFormat: StepFormat = .numbers, scale: Double = 1,
        project base: Project = .plain(padding: 20)
    ) throws -> CGImage {
        var project = base
        project.annotations = AnnotationLayer(items: items, stepFormat: stepFormat)
        let image = try content ?? Fixtures.solid(width: 400, height: 240, red: 1, green: 1, blue: 1)
        return try Renderer.render(project: project, content: image, scale: scale)
    }

    @Test("[S9-AC3] without annotations the render is byte-identical to before (S1 default snapshot)")
    func noAnnotationsUnchanged() throws {
        let content = try SampleContent.image(width: 1000, height: 600)
        var project = Project.plain()
        let before = try ImageCodec.pngData(Renderer.render(project: project, content: content))
        project.annotations.add(Annotation(kind: .pen, points: [point(10, 10), point(90, 90)]))
        project.annotations.items.removeAll()
        let after = try Renderer.render(project: project, content: content)
        #expect(try ImageCodec.pngData(after) == before)
        try assertSnapshot(after, named: "s1-default-1000x600")
    }

    @Test("[S9-AC4] a rectangle stays on the same content pixels when padding or canvas size change")
    func attachedToContent() throws {
        let box = Annotation(
            kind: .rectangle, points: [point(100, 100), point(200, 150)], color: Self.red, filled: true)
        let content = try Fixtures.solid(width: 400, height: 240, red: 1, green: 1, blue: 1)
        for padding in [64.0, 200.0] {
            let image = try render([box], content: content, project: .plain(padding: padding))
            let pixels = try PixelBuffer(image)
            #expect(pixels.pixel(x: Int(padding) + 150, y: Int(padding) + 125) == [242, 69, 61, 255])
            #expect(pixels.pixel(x: Int(padding) + 90, y: Int(padding) + 125) == [255, 255, 255, 255])
        }
        let exact = Project.plain(canvas: .exact(PixelSize(width: 1200, height: 900)), padding: 20)
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 400, height: 240), project: exact)
        let image = try render([box], content: content, project: exact)
        let x = Int(layout.contentRect.x + 150 * layout.styleScale)
        let y = Int(layout.contentRect.y + 125 * layout.styleScale)
        #expect(try PixelBuffer(image).pixel(x: x, y: y) == [242, 69, 61, 255])
    }

    @Test("[S9-AC6] pen strokes: smooth, round-capped, solid / dashed / dotted")
    func penStyles() throws {
        let wave = (0...12).map { point(30 + Double($0) * 28, 50 + sin(Double($0) / 2) * 30) }
        let items = AnnotationLineStyle.allCases.enumerated().map { index, style in
            Annotation(
                kind: .pen, points: wave.map { $0 + point(0, Double(index) * 70) }, color: Self.red, lineWidth: 6,
                lineStyle: style)
        }
        try assertSnapshot(try render(items), named: "s9-pen-styles")
        let dot = try render([Annotation(kind: .pen, points: [point(50, 50)], color: .black, lineWidth: 10)])
        #expect(try PixelBuffer(dot).pixel(x: 70, y: 70) == [0, 0, 0, 255])
    }

    @Test("[S9-AC7] the highlighter multiplies: tinted over white, black stays black")
    func highlighterMultiplies() throws {
        let content = try Fixtures.draw(width: 400, height: 240) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 240))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 240))
        }
        let stroke = Annotation(
            kind: .highlighter, points: [point(20, 120), point(380, 120)], color: RGBAColor(rgb: 0xF2D02B),
            lineWidth: 18)
        let pixels = try PixelBuffer(try render([stroke], content: content))
        let overWhite = pixels.pixel(x: 120, y: 140)
        #expect(
            overWhite[0] > 240 && overWhite[2] < 200 && overWhite[2] > 100, "a translucent yellow tint: \(overWhite)")
        #expect(pixels.pixel(x: 320, y: 140) == [0, 0, 0, 255])
        #expect(pixels.pixel(x: 120, y: 120) == [255, 255, 255, 255], "outside the stroke")
    }

    @Test("[S9-AC9] [S9-AC10] arrows with heads; outlined and filled rectangles")
    func arrowsAndRectangles() throws {
        let items = [
            Annotation(kind: .arrow, points: [point(30, 200), point(180, 40)], color: Self.red, lineWidth: 6),
            Annotation(kind: .arrow, points: [point(40, 40), point(60, 50)], color: .black, lineWidth: 3),
            Annotation(
                kind: .rectangle, points: [point(220, 30), point(370, 110)], color: RGBAColor(rgb: 0x3366E8),
                lineWidth: 6, lineStyle: .dashed),
            Annotation(
                kind: .rectangle, points: [point(220, 140), point(370, 210)], color: RGBAColor(rgb: 0x3DBE5C),
                filled: true, rotation: 10),
        ]
        try assertSnapshot(try render(items), named: "s9-arrows-rectangles")
    }

    @Test("[S9-AC11] [S9-AC12] text in three alignments and numbered / lettered steps")
    func textAndSteps() throws {
        let style: [(AnnotationTextAlignment, Double)] = [(.left, 20), (.center, 80), (.right, 140)]
        var items = style.map { alignment, y in
            Annotation(
                kind: .text, points: [point(20, y), point(220, y + 50)], color: .black, text: "Sunshot\nnote",
                fontSize: 20, alignment: alignment)
        }
        items += (0..<3).map {
            Annotation(
                kind: .step, points: [point(260 + Double($0) * 45, 30), point(300 + Double($0) * 45, 70)],
                color: $0 == 1 ? RGBAColor(rgb: 0xF2D02B) : Self.red)
        }
        try assertSnapshot(try render(items), named: "s9-text-steps")
        try assertSnapshot(try render(items, stepFormat: .letters), named: "s9-text-steps-letters")
    }

    @Test("[S9-AC14] emoji stickers render in colour and rotate")
    func stickers() throws {
        let items = [
            Annotation(kind: .sticker, points: [point(40, 40), point(140, 140)], text: "🚀"),
            Annotation(kind: .sticker, points: [point(200, 60), point(300, 160)], rotation: 30, text: "⭐"),
        ]
        let image = try render(items)
        try assertSnapshot(image, named: "s9-stickers")
        let pixels = try PixelBuffer(image)
        var colourful = 0
        for y in 60..<160 {
            for x in 60..<160 {
                let rgba = pixels.pixel(x: x, y: y)
                if Int(rgba[0]) - Int(rgba[2]) > 60 || Int(rgba[2]) - Int(rgba[0]) > 60 { colourful += 1 }
            }
        }
        #expect(colourful > 500, "the emoji is drawn in colour")
    }

    @Test("[S9-AC19] strokes are vector: 6 px at 1×, 12 px at 2×, anti-aliased")
    func vectorAtExportResolution() throws {
        let content = try Fixtures.solid(width: 1000, height: 600, red: 1, green: 1, blue: 1)
        let line = Annotation(kind: .pen, points: [point(100, 300), point(900, 300)], color: .black, lineWidth: 6)
        for scale in [1.0, 2.0] {
            let pixels = try PixelBuffer(try render([line], content: content, scale: scale))
            let column = Int(520 * scale)
            let dark = (0..<pixels.height).filter { pixels.pixel(x: column, y: $0)[0] < 128 }
            #expect(dark.count == Int(6 * scale))
            #expect(dark.first == Int(317 * scale), "centred on content y 300 → canvas 320")
        }
        let slanted = Annotation(kind: .pen, points: [point(100, 100), point(700, 400)], color: .black, lineWidth: 6)
        let pixels = try PixelBuffer(try render([slanted], content: content, scale: 2))
        let greys = Set((0..<pixels.height).map { pixels.pixel(x: 800, y: $0)[0] })
        #expect(greys.count > 4, "edges are anti-aliased, not a scaled bitmap: \(greys.sorted())")
    }

    @Test("[S9-AC19] the preview renders annotations through the same call as export")
    func previewParity() throws {
        var project = Project.plain(padding: 20)
        project.annotations.add(Annotation(kind: .arrow, points: [point(10, 10), point(200, 120)], color: Self.red))
        project.annotations.add(Annotation(kind: .redact, points: [point(50, 50), point(150, 100)]))
        let document = EditorDocument(
            project: project, content: ContentImage(try Fixtures.noise(width: 300, height: 200)))
        let preview = try #require(try Renderer.render(document: document, scale: 1, showsTransparencyGrid: true))
        let export = try #require(try Renderer.render(document: document, scale: 1))
        #expect(try ImageCodec.pngData(preview) == ImageCodec.pngData(export))
    }
}
