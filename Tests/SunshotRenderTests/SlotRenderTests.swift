import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S15: several screenshots in one render — per-device images and screenshot layouts.
@Suite("Multiple screenshots rendering")
struct SlotRenderTests {
    static let main = PixelSize(width: 400, height: 250)

    static func slotImage(_ index: Int) throws -> CGImage {
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.85, 0.3, 0.35), (0.25, 0.6, 0.9), (0.95, 0.7, 0.2)]
        let color = colors[index % colors.count]
        return try Fixtures.solid(width: 300, height: 300, red: color.0, green: color.1, blue: color.2)
    }

    static func document(_ project: Project, slots: [Int] = []) throws -> EditorDocument {
        var document = EditorDocument(
            project: project, content: ContentImage(try SampleContent.image(width: main.width, height: main.height)))
        for index in slots { document.slots[index] = ContentImage(try slotImage(index)) }
        return document
    }

    static func collage(_ id: String, frame: FrameKind = .macWindow) -> Project {
        var project = Project()
        project.frame.kind = frame
        project.collage = id
        return project
    }

    static func render(_ document: EditorDocument, scale: Double = 0.5) throws -> CGImage {
        try #require(try Renderer.render(document: document, scale: scale))
    }

    @Test("[S15-AC3] a device of an arrangement shows its own image; empty slots show the main image")
    func perDeviceImages() throws {
        var project = Project()
        project.frame.device = DeviceSelection(model: "phone", arrangement: "trio")
        let plain = try Self.render(Self.document(project))
        let mixed = try Self.render(Self.document(project, slots: [1]))
        try assertSnapshot(mixed, named: "s15-trio-slot-image")
        #expect(try PixelBuffer(plain).bytes != PixelBuffer(mixed).bytes)
        // An image keyed as the main screenshot (0) or a number the arrangement lacks changes nothing.
        let ignored = try Self.render(Self.document(project, slots: [0, 7]))
        #expect(try PixelBuffer(plain).bytes == PixelBuffer(ignored).bytes)
    }

    @Test("[S15-AC3] without slot images a multi-device render is unchanged from S12")
    func deviceUnchanged() throws {
        var project = Project()
        project.frame.device = DeviceSelection(model: "phone", arrangement: "pair")
        let image = try SampleContent.image(width: 360, height: 780)
        let direct = try Renderer.render(project: project, content: image, scale: 0.5)
        let viaDocument = try Self.render(EditorDocument(project: project, content: ContentImage(image)))
        #expect(try PixelBuffer(direct).bytes == PixelBuffer(viaDocument).bytes)
    }

    @Test("[S15-AC4] every screenshot layout draws the frame around each slot's image")
    func layouts() throws {
        for arrangement in CollageCatalog.bundled.arrangements {
            let others = Array(1..<arrangement.slots.count)
            // Leave the last screenshot empty so the fallback to the main image is covered too.
            let filled = others.count > 1 ? Array(others.dropLast()) : others
            let image = try Self.render(Self.document(Self.collage(arrangement.id), slots: filled))
            try assertSnapshot(image, named: "s15-\(arrangement.id)")
            let layout = CanvasLayout.compute(contentSize: Self.main, project: Self.collage(arrangement.id))
            #expect(image.width == Int((Double(layout.canvasSize.width) * 0.5).rounded()))
        }
    }

    @Test("[S15-AC4] layouts keep the content 1:1 and grow the Auto canvas around the primary frame box")
    func primaryUnchanged() throws {
        let single = CanvasLayout.compute(contentSize: Self.main, project: Self.collage("missing"))
        let pair = CanvasLayout.compute(contentSize: Self.main, project: Self.collage("side-by-side"))
        #expect(pair.contentRect.width == single.contentRect.width)
        #expect(pair.contentRect.height == single.contentRect.height)
        #expect(pair.canvasSize.width > single.canvasSize.width)
        #expect(pair.canvasSize.height == single.canvasSize.height)
    }

    @Test("[S15-AC4] frame none, card and a tilted layout preset render; annotations stay on the main slot")
    func styles() throws {
        var project = Self.collage("fan", frame: .none)
        project.placement = ContentPlacement(
            transform: ContentTransform(zoom: 90, tiltX: 12, tiltY: -18), layoutPresetID: "showcase")
        project.annotations = AnnotationLayer(items: [
            Annotation(
                kind: .rectangle, points: [AnnotationPoint(x: 20, y: 20), AnnotationPoint(x: 200, y: 120)],
                color: RGBAColor(rgb: 0xF2453D), filled: true)
        ])
        try assertSnapshot(Self.render(Self.document(project, slots: [1, 2])), named: "s15-fan-tilted-annotated")
        try assertSnapshot(
            Self.render(Self.document(Self.collage("cascade", frame: .card), slots: [1])), named: "s15-cascade-card")
    }

    @Test("[S15-AC8] preview and export of a layout with slot images are the same render")
    func parity() throws {
        let document = try Self.document(Self.collage("overlap"), slots: [1])
        var session = EditorSession(document: document)
        let preview = try #require(try Renderer.render(document: session.document, scale: 1))
        let export = try ImageLoader.load(try session.exportPNG(scale: 1))
        #expect(try PixelBuffer(preview).bytes == PixelBuffer(export).bytes)
        session.undo()
    }

    @Test("[S15-AC4] layout screenshots are shown whole at their own aspect, fitted into their slot")
    func fitWhole() throws {
        let frame = Frame()
        let wide = try Fixtures.solid(width: 800, height: 100)
        let box = CollageRenderer.naturalBox(for: wide, contentHeight: 250, frame: frame)
        #expect(box == CGSize(width: 2000, height: 250))
        #expect(CollageRenderer.fitFactor(box, in: CGSize(width: 400, height: 250)) == 0.2)
        #expect(CollageRenderer.fitFactor(CGSize(width: 100, height: 400), in: CGSize(width: 400, height: 200)) == 0.5)
        #expect(CollageRenderer.fitFactor(.zero, in: CGSize(width: 1, height: 1)) == 1)
        var window = Frame()
        window.kind = .macWindow
        let chrome = FrameGeometry.insets(for: window, contentWidth: 2000)  // S17-AC10: grows with width
        let framed = CollageRenderer.naturalBox(for: wide, contentHeight: 250, frame: window)
        #expect(framed.width == 2000 + chrome.horizontal && framed.height == 250 + chrome.vertical)

        // A wide second screenshot keeps every pixel column: its right edge is still drawn.
        var project = Self.collage("side-by-side", frame: .none)
        project.shadow = Shadow(style: .none)
        var document = try Self.document(project)
        document.slots[1] = ContentImage(try Fixtures.solid(width: 1000, height: 100, red: 1, green: 0, blue: 0))
        let image = try Self.render(document, scale: 1)
        let layout = CanvasLayout.compute(contentSize: Self.main, project: project)
        let pixels = try PixelBuffer(image)
        let right = Int(layout.frameRect.x + layout.frameRect.width) - 2
        let middle = Int(layout.frameRect.y + layout.frameRect.height / 2)
        #expect(pixels.pixel(x: right, y: middle).prefix(3) == [255, 0, 0])
    }
}
