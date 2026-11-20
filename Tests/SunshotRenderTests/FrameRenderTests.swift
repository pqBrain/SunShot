import CoreGraphics
import CoreText
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Frame snapshots and pixel checks. Pixel coordinates have a top-left origin; with the default padding the frame
/// box starts at (64, 64) on an Auto canvas.
@Suite("Frame rendering")
struct FrameRenderTests {
    static let pad = 64

    static func project(
        _ kind: FrameKind, title: String = "Release notes", appearance: ChromeAppearance = .auto,
        colors: ColorTokens = ColorTokens(), uiScale: Double = 100, shadow: Shadow = Shadow()
    ) -> Project {
        var project = Project(shadow: shadow)
        project.frame = Frame(kind: kind, title: title, uiScale: uiScale)
        project.tokens = DesignTokens(colors: colors, chromeAppearance: appearance)
        return project
    }

    static func render(_ project: Project, width: Int = 800, height: Int = 500, scale: Double = 1) throws -> CGImage {
        try Renderer.render(project: project, content: SampleContent.image(width: width, height: height), scale: scale)
    }

    static func near(_ pixel: [UInt8], _ color: RGBAColor, tolerance: Int = 1) -> Bool {
        let expected = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        return zip(pixel.prefix(3), expected).allSatisfy { abs(Int($0) - $1) <= tolerance }
    }

    @Test("[S5-AC2] frame none is the default and renders byte-identically to the S2 default")
    func noneIsDefault() throws {
        #expect(Project().frame == Frame())
        #expect(Project().frame.kind == .none)
        let content = try SampleContent.image(width: 320, height: 200)
        let image = try Renderer.render(project: Project(), content: content)
        try assertSnapshot(image, named: "s2-border-default", tolerance: 0, maxDifferingFraction: 0)
        var explicit = Project()
        explicit.frame = Frame(kind: .none, title: "Ignored", uiScale: 200)
        let other = try Renderer.render(project: explicit, content: content)
        #expect(try PixelBuffer(other).bytes == PixelBuffer(image).bytes)
    }

    @Test("[S5-AC3] mac window: 28 px bar, traffic lights, centred title, shared corners and shadow")
    func macWindow() throws {
        let light = try Self.render(Self.project(.macWindow, appearance: .light))
        #expect((light.width, light.height) == (928, 656))
        let pixels = try PixelBuffer(light)
        let barMid = Self.pad + 14
        // Three circles 12 px wide, 8 px apart, 12 px from the left: centres at 18, 38, 58.
        for (offset, color) in zip([18, 38, 58], FrameChrome.trafficLights) {
            #expect(Self.near(pixels.pixel(x: Self.pad + offset, y: barMid), color, tolerance: 2), "\(offset)")
        }
        // Between the circles is bar, and the content starts right below the bar.
        #expect(Self.near(pixels.pixel(x: Self.pad + 28, y: barMid), ChromePalette.light.bar))
        #expect(Self.near(pixels.pixel(x: Self.pad + 20, y: Self.pad + 28 + 80), RGBAColor.white))
        // Rounded silhouette: the very corner is backdrop, not bar.
        #expect(!Self.near(pixels.pixel(x: Self.pad, y: Self.pad), ChromePalette.light.bar, tolerance: 6))
        try assertSnapshot(light, named: "s5-mac-light")
        try assertSnapshot(Self.render(Self.project(.macWindow, appearance: .dark)), named: "s5-mac-dark")
    }

    @Test("[S5-AC3] a long title is truncated with … inside its slot")
    func macTruncation() throws {
        let geometry = FrameGeometry(frame: Frame(kind: .macWindow), boxWidth: 300, boxHeight: 228)
        let slot = try #require(geometry.titleRect)
        let font = FrameFonts.font("", size: FrameMetrics.titleFontSize)
        let long = String(repeating: "Release notes ", count: 8)
        let line = FrameText.truncatedLine(long, font: font, color: .black, maxWidth: slot.width)
        #expect(CTLineGetTypographicBounds(line, nil, nil, nil) <= slot.width + 0.5)
        #expect(CTLineGetGlyphCount(line) < long.count)
        let short = FrameText.truncatedLine("Hi", font: font, color: .black, maxWidth: slot.width)
        #expect(CTLineGetGlyphCount(short) == 2)
        try assertSnapshot(
            Self.render(Self.project(.macWindow, title: long), width: 300, height: 200), named: "s5-mac-truncated")
    }

    @Test("[S5-AC4] browser window: 44 px toolbar, controls, navigation and address field")
    func browserWindow() throws {
        #expect(FrameChrome.addressPlaceholder == "example.com")
        let geometry = FrameGeometry(frame: Frame(kind: .browserWindow), boxWidth: 800, boxHeight: 544)
        let field = try #require(geometry.addressField)
        let light = try Self.render(Self.project(.browserWindow, title: "", appearance: .light))
        #expect((light.width, light.height) == (928, 672))
        let pixels = try PixelBuffer(light)
        #expect(Self.near(pixels.pixel(x: Self.pad + Int(field.x) + 4, y: Self.pad + 22), ChromePalette.light.field))
        #expect(Self.near(pixels.pixel(x: Self.pad + 20, y: Self.pad + 44 + 80), RGBAColor.white))
        try assertSnapshot(light, named: "s5-browser-light")
        try assertSnapshot(Self.render(Self.project(.browserWindow, appearance: .dark)), named: "s5-browser-dark")
        // Too narrow for an address field: the toolbar still draws, without one.
        #expect(FrameGeometry(frame: Frame(kind: .browserWindow), boxWidth: 120, boxHeight: 100).addressField == nil)
    }

    @Test("[S5-AC5] Windows-style window: 32 px bar, left title, caption glyphs on the right")
    func winWindow() throws {
        let light = try Self.render(Self.project(.winWindow, appearance: .light))
        #expect((light.width, light.height) == (928, 660))
        let pixels = try PixelBuffer(light)
        // The close glyph's centre (an ×) is drawn in the title colour, 23 px from the right edge.
        let close = pixels.pixel(x: Self.pad + 800 - 23, y: Self.pad + 16)
        #expect(!Self.near(close, ChromePalette.light.bar, tolerance: 20))
        try assertSnapshot(light, named: "s5-win-light")
        try assertSnapshot(Self.render(Self.project(.winWindow, appearance: .dark)), named: "s5-win-dark")
    }

    @Test("[S5-AC6] card, stack and stack 2 on 800×500 content")
    func cards() throws {
        let colors = ColorTokens(background: RGBAColor(rgb: 0xFFF4E0))
        for (kind, name) in [
            (FrameKind.card, "s5-card"), (.stack, "s5-stack"), (.stack2, "s5-stack2"), (.stack3, "s5-stack3"),
            (.stack4, "s5-stack4"),
        ] {
            let image = try Self.render(Self.project(kind, colors: colors))
            let behind = Int(FrameGeometry.insets(for: Frame(kind: kind)).top) - 24
            #expect((image.width, image.height) == (800 + 48 + 128, 500 + 48 + behind + 128))
            let pixels = try PixelBuffer(image)
            // Card colour in the 24 px padding beside the content.
            #expect(Self.near(pixels.pixel(x: Self.pad + 12, y: image.height / 2), colors.background), "\(kind)")
            // Content starts 24 px in (below the sample's dark top strip).
            #expect(Self.near(pixels.pixel(x: Self.pad + 24 + 10, y: Self.pad + behind + 24 + 80), .white))
            try assertSnapshot(image, named: name)
        }
    }

    @Test("[S5-AC7] thick border: 14 px ring in the Secondary token, concentric corners")
    func thickBorder() throws {
        let image = try Self.render(Self.project(.thickBorder, appearance: .light))
        #expect((image.width, image.height) == (928 + 28, 628 + 28))
        let pixels = try PixelBuffer(image)
        #expect(Self.near(pixels.pixel(x: Self.pad + 7, y: image.height / 2), SunshotDefaults.secondaryColor))
        #expect(Self.near(pixels.pixel(x: Self.pad + 14 + 10, y: image.height / 2), .white))
        try assertSnapshot(image, named: "s5-thick-light")
        let dark = ColorTokens(
            foreground: RGBAColor(rgb: 0xF2F2F7), background: RGBAColor(rgb: 0x101014),
            secondary: RGBAColor(rgb: 0x3A3A40))
        try assertSnapshot(Self.render(Self.project(.thickBorder, colors: dark)), named: "s5-thick-dark")
    }

    @Test("[S5-AC13] tokens drive the chrome; backdrop and content pixels are untouched")
    func tokensDriveChrome() throws {
        let magenta = RGBAColor(rgb: 0xFF00FF)
        let green = RGBAColor(rgb: 0x00FF00)
        let tokens = ColorTokens(foreground: magenta, background: green)
        let none = Shadow(style: .none)
        let custom = try Self.render(
            Self.project(.macWindow, title: "HHHH", colors: tokens, uiScale: 200, shadow: none))
        let plain = try Self.render(Self.project(.macWindow, title: "HHHH", uiScale: 200, shadow: none))
        let pixels = try PixelBuffer(custom)
        let reference = try PixelBuffer(plain)
        // Bar fill: right part of the bar, away from title and lights.
        #expect(Self.near(pixels.pixel(x: Self.pad + 760, y: Self.pad + 20), green))
        // Some title pixel is the exact foreground colour (glyph stems at 26 pt are several pixels wide).
        let titleRow = (Self.pad + 10)..<(Self.pad + 46)
        let titleCols = (Self.pad + 300)..<(Self.pad + 500)
        let hit = titleRow.contains { y in titleCols.contains { x in Self.near(pixels.pixel(x: x, y: y), magenta) } }
        #expect(hit)
        // Backdrop and content are identical to the default-token render.
        #expect(pixels.pixel(x: 5, y: 5) == reference.pixel(x: 5, y: 5))
        for y in stride(from: Self.pad + 56 + 5, to: Self.pad + 56 + 495, by: 37) {
            #expect(pixels.pixel(x: Self.pad + 401, y: y) == reference.pixel(x: Self.pad + 401, y: y))
        }
    }

    @Test("[S19-AC2] dark chrome gives card and stack frames a dark card; auto and light keep the Background token")
    func darkCards() throws {
        let colors = ColorTokens(background: RGBAColor(rgb: 0xFFF4E0))
        for kind in [FrameKind.card, .stack3, .stack4] {
            let image = try Self.render(Self.project(kind, appearance: .dark, colors: colors))
            let pixels = try PixelBuffer(image)
            #expect(Self.near(pixels.pixel(x: Self.pad + 12, y: image.height / 2), ChromePalette.dark.body), "\(kind)")
        }
    }

    @Test("[S5-AC17] transparent content shows the card colour (card) or the window body (chrome), never the backdrop")
    func transparentContent() throws {
        let clear = try Fixtures.draw(width: 200, height: 120) { _ in }
        let colors = ColorTokens(background: RGBAColor(rgb: 0x336699))
        for kind in [FrameKind.card, .stack, .macWindow] {
            let project = Self.project(kind, appearance: .light, colors: colors)
            let image = try Renderer.render(project: project, content: clear)
            let pixels = try PixelBuffer(image)
            let expected = kind == .macWindow ? ChromePalette.light.body : colors.background
            #expect(Self.near(pixels.pixel(x: image.width / 2, y: image.height - Self.pad - 40), expected), "\(kind)")
        }
    }

    @Test("[S5-AC18] preview and export are byte-identical with a browser frame, high shadow and gradient")
    func parity() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 640, height: 400))
        session.applyGradientPreset(SunshotDefaults.gradient)
        session.setShadowIntensity(.high)
        session.setFrameKind(.browserWindow)
        session.setFrameTitle("sunshot.app/notes")
        for scale in [1.0, 2.0] {
            let preview = try #require(
                try Renderer.render(document: session.document, scale: scale, showsTransparencyGrid: true))
            let export = try ImageCodec.decode(ImageCodec.pngData(#require(try session.render(scale: scale))))
            #expect(try PixelBuffer(preview).bytes == PixelBuffer(export).bytes, "scale \(scale)")
        }
    }

    @Test("[S5-AC19] frame chrome is vector-sharp at 4K: the window edge transition is ≤ 2 px")
    func vectorSharp() throws {
        let project = Self.project(.macWindow, appearance: .dark, shadow: Shadow(style: .none))
        let scale = 3840.0 / 928.0
        let big = try Self.render(project, scale: scale)
        let pixels = try PixelBuffer(big)
        let backdrop = SunshotDefaults.backdropColor
        let bar = ChromePalette.dark.bar
        let x = big.width * 3 / 4
        let rows = 0..<Int(Double(Self.pad + 20) * scale)
        let between = rows.filter { y in
            let pixel = pixels.pixel(x: x, y: y)
            return !Self.near(pixel, backdrop, tolerance: 2) && !Self.near(pixel, bar, tolerance: 2)
        }
        #expect(between.count <= 2, "transition rows \(between)")
        try assertSnapshot(Self.render(project, scale: 1), named: "s5-mac-dark-1x")
    }
}
