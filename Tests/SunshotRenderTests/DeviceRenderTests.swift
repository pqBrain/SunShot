import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Device mockup snapshots and pixel checks (S12). Pixel coordinates have a top-left origin; with the default
/// padding the frame box starts at (64, 64) on an Auto canvas.
@Suite("Device rendering")
struct DeviceRenderTests {
    static func project(
        _ model: String, finish: String = "graphite", landscape: Bool = false, arrangement: String = "single"
    ) -> Project {
        var project = Project()
        project.frame.device = DeviceSelection(
            model: model, finish: finish, landscape: landscape, arrangement: arrangement)
        return project
    }

    static func render(_ project: Project, width: Int, height: Int, scale: Double = 1) throws -> CGImage {
        try Renderer.render(project: project, content: SampleContent.image(width: width, height: height), scale: scale)
    }

    @Test("[S12-AC6] phone, landscape tablet, laptop and monitor match their snapshots")
    func devices() throws {
        let phone = try Self.render(Self.project("phone"), width: 360, height: 780)
        #expect((phone.width, phone.height) == (534, 948))
        try assertSnapshot(phone, named: "s12-phone-graphite")
        try assertSnapshot(
            Self.render(Self.project("tablet", finish: "silver", landscape: true), width: 400, height: 300),
            named: "s12-tablet-landscape-silver")
        try assertSnapshot(
            Self.render(Self.project("laptop", finish: "sand"), width: 400, height: 250), named: "s12-laptop-sand")
        try assertSnapshot(
            Self.render(Self.project("desktop", finish: "sage"), width: 480, height: 270), named: "s12-monitor-sage")
    }

    @Test("[S12-AC3] a device this version doesn't know renders the plain content")
    func unknownDevice() throws {
        let plain = try Self.render(Project(), width: 320, height: 200)
        let unknown = try Self.render(Self.project("hologram"), width: 320, height: 200)
        #expect(try PixelBuffer(unknown).bytes == PixelBuffer(plain).bytes)
    }

    @Test("[S12-AC7] finishes recolour the shell; the screen pixels stay identical")
    func finishes() throws {
        var shells: [[UInt8]] = []
        var screens: [[UInt8]] = []
        for finish in ["graphite", "silver", "sand", "sage"] {
            let pixels = try PixelBuffer(Self.render(Self.project("phone", finish: finish), width: 360, height: 780))
            // Shell: just inside the left edge, above the side buttons.
            shells.append(Array(pixels.pixel(x: 64 + 3 + 4, y: 64 + 120).prefix(3)))
            var screen: [UInt8] = []
            for y in stride(from: 64 + 20 + 60, to: 64 + 20 + 720, by: 37) {
                for x in stride(from: 64 + 23 + 50, to: 64 + 23 + 310, by: 29) { screen += pixels.pixel(x: x, y: y) }
            }
            screens.append(screen)
        }
        #expect(Set(shells).count == 4)
        #expect(Set(screens).count == 1)
        // Graphite is dark, silver light.
        #expect(shells[0].map(Int.init).reduce(0, +) < 3 * 128 && shells[1].map(Int.init).reduce(0, +) > 3 * 160)
    }

    @Test("[S12-AC9] multi-device layouts show the same content on every screen in one render")
    func arrangements() throws {
        let cases: [(String, String, Int, Int)] = [
            ("phone", "pair", 360, 780), ("phone", "trio", 360, 780), ("laptop", "laptop-phone", 400, 250),
            ("desktop", "monitor-phone", 480, 270), ("tablet", "tablet-phone", 300, 400),
        ]
        for (model, arrangement, width, height) in cases {
            let project = Self.project(model, finish: model == "phone" ? "sand" : "silver", arrangement: arrangement)
            let image = try Self.render(project, width: width, height: height, scale: 0.5)
            try assertSnapshot(image, named: "s12-\(arrangement)")
            let layout = CanvasLayout.compute(contentSize: PixelSize(width: width, height: height), project: project)
            #expect(image.width == Int((Double(layout.canvasSize.width) * 0.5).rounded()))
        }
    }

    @Test("[S12-AC10] a tilted device layout casts one shadow and moves as one object")
    func tiltedDevice() throws {
        var project = Self.project("phone", arrangement: "pair")
        project.placement = ContentPlacement(
            transform: ContentTransform(zoom: 90, tiltX: 16, tiltY: -24), layoutPresetID: "showcase")
        let image = try Self.render(project, width: 360, height: 780, scale: 0.5)
        try assertSnapshot(image, named: "s12-pair-tilted-shadow")
        // The flat version differs (the transform applies to the device too).
        var flat = project
        flat.placement = ContentPlacement()
        #expect(
            try PixelBuffer(Self.render(flat, width: 360, height: 780, scale: 0.5)).bytes != PixelBuffer(image).bytes)
    }

    @Test("[S12-AC11] preview and export are the same render; 2× doubles the canvas")
    func parity() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 400, height: 250))
        session.setDevice("laptop")
        let canvas = try #require(session.canvasSize)
        let preview = try #require(
            try Renderer.render(document: session.document, scale: 1, showsTransparencyGrid: true))
        let export = try ImageLoader.load(try session.exportPNG(scale: 1))
        #expect(try PixelBuffer(preview).bytes == PixelBuffer(export).bytes)
        let double = try ImageLoader.load(try session.exportPNG(scale: 2))
        #expect((double.width, double.height) == (canvas.width * 2, canvas.height * 2))
    }

    @Test("[S12-AC21] existing annotations draw on the primary screen with the content")
    func annotationsOnScreen() throws {
        var project = Self.project("phone")
        let red = RGBAColor(rgb: 0xFF0000)
        project.annotations.add(
            Annotation(
                kind: .rectangle, points: [AnnotationPoint(x: 100, y: 300), AnnotationPoint(x: 200, y: 400)],
                color: red, filled: true))
        let pixels = try PixelBuffer(Self.render(project, width: 360, height: 780))
        let pixel = pixels.pixel(x: 64 + 23 + 150, y: 64 + 20 + 350)
        #expect(pixel[0] > 240 && pixel[1] < 20 && pixel[2] < 20)
    }

    @Test("[S12-AC4] wide content is centre-cropped into a phone screen, not scaled")
    func cropRender() throws {
        // A 1000×400 image whose left and right thirds are red, centre blue: the phone shows only blue.
        let content = try Fixtures.draw(width: 1000, height: 400) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 400, y: 0, width: 200, height: 400))
        }
        let project = Self.project("phone")
        let image = try Renderer.render(project: project, content: content)
        let layout = CanvasLayout.compute(contentSize: PixelSize(width: 1000, height: 400), project: project)
        #expect(abs(layout.contentRect.width - 400 * 360.0 / 780) < 1e-9)
        let pixels = try PixelBuffer(image)
        let rect = layout.contentRect
        for x in [rect.x + 20, rect.midX, rect.x + rect.width - 20] {
            let pixel = pixels.pixel(x: Int(x), y: Int(rect.midY))
            #expect(pixel[2] > 200 && pixel[0] < 40, "x \(x)")
        }
    }
}
