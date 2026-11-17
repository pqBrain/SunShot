import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S6: position, zoom, rotation and tilt in the one render function.
@Suite("Content transform rendering")
struct TransformRenderTests {
    static let backdrop: [UInt8] = [237, 237, 242, 255]

    static func project(_ transform: ContentTransform, padding: Double = 64) -> Project {
        var project = Project.plain(padding: padding)
        project.placement.transform = transform
        return project
    }

    /// Bounding box of pixels that clearly differ from the backdrop (more than half-way to the content colour).
    static func contentBounds(_ image: CGImage) throws -> (minX: Int, minY: Int, width: Int, height: Int) {
        let pixels = try PixelBuffer(image)
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where isContent(pixels.pixel(x: x, y: y)) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// The solid fixture is (51, 128, 204): its red channel is far from the backdrop's 237.
    static func isContent(_ pixel: [UInt8]) -> Bool { pixel[0] < 144 }

    /// Rows of content in one column.
    static func columnHeight(_ pixels: PixelBuffer, x: Int) -> Int {
        (0..<pixels.height).filter { isContent(pixels.pixel(x: x, y: $0)) }.count
    }

    static func bytes(_ image: CGImage) throws -> [UInt8] { try PixelBuffer(image).bytes }

    @Test("[S6-AC1] the identity transform is the default and the render is byte-identical to before S6")
    func identityUnchanged() throws {
        #expect(Project().placement.transform == .identity)
        #expect(Project().placement.layoutPresetID == nil)
        let content = try SampleContent.image(width: 1000, height: 600)
        var session = EditorSession(document: EditorDocument(project: .plain()))
        session.setContent(content)
        let image = try #require(try session.render())
        try assertSnapshot(image, named: "s1-default-1000x600", tolerance: 0, maxDifferingFraction: 0)
        // A selected preset whose transform is the identity draws the same bytes.
        var selected = Project()
        selected.placement = ContentPlacement(transform: .identity, layoutPresetID: "centered")
        let plain = try Renderer.render(project: Project(), content: content)
        #expect(try Self.bytes(Renderer.render(project: selected, content: content)) == Self.bytes(plain))
    }

    @Test("[S6-AC3] [S6-AC5] an offset moves the content by that share of the canvas; ±0.5 puts its centre on the edge")
    func offsetMovesContent() throws {
        let content = try Fixtures.solid(width: 200, height: 100)
        let image = try Renderer.render(project: Self.project(ContentTransform(x: 0.25, y: 0.1)), content: content)
        let bounds = try Self.contentBounds(image)
        // Canvas 328×228: centre moves by 82 / 22.8 px from (164, 114).
        #expect(abs(Double(bounds.minX) + 100 - (164 + 82)) <= 1)
        #expect(abs(Double(bounds.minY) + 50 - (114 + 22.8)) <= 1)
        let edge = try Renderer.render(project: Self.project(ContentTransform(x: 0.5)), content: content)
        let edgeBounds = try Self.contentBounds(edge)
        #expect(abs(edgeBounds.minX - (328 - 100)) <= 1)
        #expect(edgeBounds.width == 100)
    }

    @Test("[S6-AC6] 200 % zoom doubles the content about its centre and doesn't change an Auto canvas")
    func zoomScalesContent() throws {
        let content = try Fixtures.solid(width: 200, height: 100)
        let flat = try Renderer.render(project: Self.project(.identity, padding: 120), content: content)
        let zoomed = try Renderer.render(
            project: Self.project(ContentTransform(zoom: 200), padding: 120), content: content)
        #expect((zoomed.width, zoomed.height) == (flat.width, flat.height))
        let bounds = try Self.contentBounds(zoomed)
        #expect(abs(bounds.width - 400) <= 1 && abs(bounds.height - 200) <= 1, "\(bounds)")
        #expect(abs(bounds.minX - (440 - 400) / 2) <= 1)
    }

    @Test(
        "[S6-AC7] rotation turns the content about its centre; 90° swaps extents, 45° gives 495×495",
        arguments: [(0.0, 400, 300), (90, 300, 400), (-90, 300, 400), (180, 400, 300), (45, 495, 495), (270, 300, 400)])
    func rotationExtents(degrees: Double, width: Int, height: Int) throws {
        let content = try Fixtures.solid(width: 400, height: 300)
        let project = Self.project(ContentTransform(rotation: degrees), padding: 200)
        let image = try Renderer.render(project: project, content: content)
        let bounds = try Self.contentBounds(image)
        #expect(abs(bounds.width - width) <= 1 && abs(bounds.height - height) <= 1, "\(bounds)")
        // Centred: the box's middle stays at the canvas centre (400, 350).
        #expect(abs(Double(bounds.minX) + Double(bounds.width) / 2 - 400) <= 1)
        // No seams or lost pixels: everything within 140 px of the centre is content.
        let pixels = try PixelBuffer(image)
        for y in stride(from: 350 - 140, through: 350 + 140, by: 7) {
            for x in stride(from: 400 - 140, through: 400 + 140, by: 7)
            where hypot(Double(x - 400), Double(y - 350)) < 140 {
                #expect(pixels.pixel(x: x, y: y) == [51, 128, 204, 255], "(\(x), \(y))")
            }
        }
    }

    @Test("[S6-AC8] rotation keeps border and shadow attached; the shadow still falls toward the light's opposite")
    func rotationKeepsStyle() throws {
        let content = try SampleContent.image(width: 400, height: 260)
        var project = Project(
            padding: 120, border: Border(style: .smooth, radius: 40), shadow: Shadow(style: .spread, intensity: .high))
        project.placement.transform = ContentTransform(rotation: 20)
        let image = try Renderer.render(project: project, content: content)
        try assertSnapshot(image, named: "s6-rotation-20-border-shadow")
        // The default light is above: the shadow is darker below the rotated content than above it.
        let pixels = try PixelBuffer(image)
        let projection = ContentProjection(
            contentRect: LayoutRect(x: 120, y: 120, width: 400, height: 260),
            canvasSize: PixelSize(width: 640, height: 500), transform: project.placement.transform)
        // Along the vertical through the centre, the rotated edges are (130 / cos 20°) from the centre.
        let reach = 130 / cos(20 * Double.pi / 180)
        #expect(abs(projection.center.y - 250) < 0.001)
        let below = pixels.pixel(x: 320, y: Int(250 + reach) + 10)
        let above = pixels.pixel(x: 320, y: Int(250 - reach) - 10)
        #expect(Int(below[0]) + 8 < Int(above[0]), "below \(below) above \(above)")
    }

    @Test("[S6-AC9] tilt renders with perspective: the near edge is taller by the 4× camera ratio (±2 %)")
    func tiltPerspective() throws {
        let content = try Fixtures.solid(width: 800, height: 600)
        let tilted = ContentTransform(tiltY: 30)
        let image = try Renderer.render(project: Self.project(tilted, padding: 200), content: content)
        let bounds = try Self.contentBounds(image)
        let pixels = try PixelBuffer(image)
        let near = Double(Self.columnHeight(pixels, x: bounds.minX + 3))
        let far = Double(Self.columnHeight(pixels, x: bounds.minX + bounds.width - 4))
        let distance = 4.0 * 800
        let lean = 400 * sin(30 * Double.pi / 180)
        let expected = (distance + lean) / (distance - lean)
        #expect(abs(near / far / expected - 1) <= 0.02, "ratio \(near / far) vs \(expected)")
        // The tilted width is narrower than flat.
        #expect(bounds.width < 800 && bounds.width > 650)
        try assertSnapshot(image, named: "s6-tilt-y30")

        // Positive tilt X leans the top away: the bottom row is wider than the top row.
        let topAway = try Renderer.render(
            project: Self.project(ContentTransform(tiltX: 30), padding: 200), content: content)
        let topBounds = try Self.contentBounds(topAway)
        let topPixels = try PixelBuffer(topAway)
        func rowWidth(_ y: Int) -> Int {
            (0..<topPixels.width).filter { Self.isContent(topPixels.pixel(x: $0, y: y)) }.count
        }
        #expect(rowWidth(topBounds.minY + topBounds.height - 4) > rowWidth(topBounds.minY + 3))
    }

    @Test("[S6-AC9] tilt 0/0 is exactly the flat render")
    func zeroTiltIsFlat() throws {
        let content = try SampleContent.image(width: 300, height: 200)
        var flat = Project()
        flat.placement.transform = ContentTransform(zoom: 90, rotation: 12)
        var zeroTilt = flat
        zeroTilt.placement.transform.tiltX = -0.0
        zeroTilt.placement.transform.tiltY = 0
        #expect(
            try Self.bytes(Renderer.render(project: flat, content: content))
                == Self.bytes(Renderer.render(project: zeroTilt, content: content)))
    }

    static func parityDocument() throws -> EditorDocument {
        var project = Project(
            border: Border(style: .smooth, radius: 30), shadow: Shadow(style: .spread, intensity: .high))
        project.placement.transform = ContentTransform(x: 0.1, y: -0.05, zoom: 120, rotation: 10, tiltX: 20, tiltY: -25)
        return EditorDocument(project: project, content: ContentImage(try SampleContent.image(width: 480, height: 300)))
    }

    @Test("[S6-AC10] tilted preview and export are byte-identical at 1× and 2×; 2× ≈ 1× (SSIM ≥ 0.98)")
    func tiltParity() throws {
        let document = try Self.parityDocument()
        let session = EditorSession(document: document)
        for scale in [1.0, 2.0] {
            let preview = try #require(try Renderer.render(document: document, scale: scale))
            let exported = try ImageCodec.decode(try session.exportPNG(scale: scale))
            #expect(try Self.bytes(preview) == Self.bytes(exported), "scale \(scale)")
        }
        let one = try #require(try Renderer.render(document: document, scale: 1))
        let two = try #require(try Renderer.render(document: document, scale: 2))
        let downscaled = try #require(BorderShadowRenderTests.resize(two, width: one.width, height: one.height))
        let ssim = BorderShadowRenderTests.ssim(try PixelBuffer(one), try PixelBuffer(downscaled))
        #expect(ssim >= 0.98, "SSIM \(ssim)")
        try assertSnapshot(one, named: "s6-tilt-parity-1x")
    }

    @Test("[S6-AC11] extreme transforms render safely; 1×1 content at 400 % covers 4×4 px")
    func extremeTransforms() throws {
        let content = try Fixtures.solid(width: 1200, height: 1200)
        let extreme = ContentTransform(zoom: 400, rotation: 180, tiltX: 60, tiltY: 60)
        let projection = ContentProjection(
            contentRect: LayoutRect(x: 64, y: 64, width: 1200, height: 1200),
            canvasSize: PixelSize(width: 1328, height: 1328),
            transform: extreme)
        #expect(projection.corners.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        let image = try Renderer.render(project: Self.project(extreme), content: content)
        #expect((image.width, image.height) == (1328, 1328))
        #expect(Self.isContent(try PixelBuffer(image).pixel(x: 664, y: 664)))

        let tiny = try Fixtures.solid(width: 1, height: 1)
        // The 129 px canvas centres the dot on a half pixel; shift it by half a pixel so it is pixel-aligned.
        let aligned = ContentTransform(x: 0.5 / 129, y: 0.5 / 129, zoom: 400)
        let dot = try Renderer.render(project: Self.project(aligned), content: tiny)
        let bounds = try Self.contentBounds(dot)
        #expect(bounds == (63, 63, 4, 4), "\(bounds)")
        let pixels = try PixelBuffer(dot)
        for y in 62..<68 {
            for x in 62..<68 {
                let inside = (63..<67).contains(x) && (63..<67).contains(y)
                #expect(pixels.pixel(x: x, y: y) == (inside ? [51, 128, 204, 255] : Self.backdrop), "(\(x), \(y))")
            }
        }
        // A tilted 1×1 doesn't crash either.
        _ = try Renderer.render(
            project: Self.project(ContentTransform(zoom: 400, tiltX: 60, tiltY: -60)), content: tiny)
    }

    @Test("[S6-AC11] content pushed wholly off the canvas still renders the backdrop")
    func offCanvas() throws {
        let content = try Fixtures.solid(width: 100, height: 100)
        var transform = ContentTransform(x: 0.5, y: 0.5, zoom: 25, tiltX: 40)
        transform.x = 0.5
        let image = try Renderer.render(project: Self.project(transform, padding: 400), content: content)
        let pixels = try PixelBuffer(image)
        #expect(pixels.pixel(x: 10, y: 10) == Self.backdrop)
    }
}
