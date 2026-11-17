import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Pixel checks use a top-left origin; content sits at (64, 64) on an auto canvas.
@Suite("Border and shadow rendering")
struct BorderShadowRenderTests {
    private static let pad = 64
    private static let backdrop: [UInt8] = [237, 237, 242, 255]
    private let contentColor: [UInt8] = [51, 128, 204, 255]

    private func render(
        _ border: Border, _ shadow: Shadow = Shadow(style: .none), content: CGImage? = nil, scale: Double = 1
    ) throws -> CGImage {
        let image = try content ?? Fixtures.solid(width: 200, height: 120)
        return try Renderer.render(project: Project(border: border, shadow: shadow), content: image, scale: scale)
    }

    private func isContent(_ pixel: [UInt8]) -> Bool {
        zip(pixel, contentColor).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
    }

    /// First diagonal step (from the content's top-left corner) that is fully content-coloured.
    private func diagonalInset(_ image: CGImage) throws -> Int {
        let pixels = try PixelBuffer(image)
        for step in 0..<60 where isContent(pixels.pixel(x: Self.pad + step, y: Self.pad + step)) { return step }
        return -1
    }

    private func luminance(_ pixel: [UInt8]) -> Double {
        0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])
    }

    /// Darkest point below the content (centre column): backdrop luminance minus the minimum.
    private func shadowDarkness(_ image: CGImage) throws -> Double {
        let pixels = try PixelBuffer(image)
        let backdrop = luminance(Self.backdrop)
        let x = image.width / 2
        let rows = (image.height - Self.pad)..<image.height
        return backdrop - (rows.map { luminance(pixels.pixel(x: x, y: $0)) }.min() ?? backdrop)
    }

    @Test("[S2-AC2] default border and shadow render")
    func defaultLook() throws {
        try assertSnapshot(
            Renderer.render(project: Project(), content: SampleContent.image(width: 320, height: 200)),
            named: "s2-border-default")
    }

    @Test("[S2-AC3] sharp ignores the radius; round and smooth round the corner with distinct silhouettes")
    func cornerStyles() throws {
        let content = try Fixtures.solid(width: 400, height: 300)
        let sharp = try render(Border(style: .sharp, radius: 40), content: content)
        let round = try render(Border(style: .round, radius: 40), content: content)
        let smooth = try render(Border(style: .smooth, radius: 40), content: content)

        #expect(try isContent(PixelBuffer(sharp).pixel(x: Self.pad, y: Self.pad)))
        #expect(try PixelBuffer(round).pixel(x: Self.pad, y: Self.pad) == Self.backdrop)
        #expect(try PixelBuffer(smooth).pixel(x: Self.pad, y: Self.pad) == Self.backdrop)

        // Circular corner: the arc crosses the diagonal r(1 − 1/√2) ≈ 11.7 px in.
        let roundInset = try diagonalInset(round)
        #expect((11...13).contains(roundInset), "round inset \(roundInset)")
        let smoothInset = try diagonalInset(smooth)
        #expect(abs(smoothInset - roundInset) >= 1, "smooth \(smoothInset) vs round \(roundInset)")
        // Same bounding box: the middle of every edge is content.
        let pixels = try PixelBuffer(smooth)
        for (x, y) in [(Self.pad + 200, Self.pad), (Self.pad, Self.pad + 150), (Self.pad + 399, Self.pad + 150)] {
            #expect(isContent(pixels.pixel(x: x, y: y)))
        }
        try assertSnapshot(sharp, named: "s2-corner-sharp")
        try assertSnapshot(round, named: "s2-corner-round")
        try assertSnapshot(smooth, named: "s2-corner-smooth")
    }

    @Test("[S2-AC5] a radius above half the content is limited without artefacts")
    func oversizedRadius() throws {
        let content = try Fixtures.solid(width: 100, height: 60)
        for style in [CornerStyle.round, .smooth] {
            let image = try render(Border(style: style, radius: 200), content: content)
            let pixels = try PixelBuffer(image)
            #expect(isContent(pixels.pixel(x: Self.pad + 50, y: Self.pad + 30)), "centre filled")
            #expect(isContent(pixels.pixel(x: Self.pad + 50, y: Self.pad + 1)), "top edge middle filled")
            #expect(pixels.pixel(x: Self.pad + 1, y: Self.pad + 1) == Self.backdrop, "corner cut")
            // No inverted corners: nothing outside the content rect is content-coloured.
            #expect(!isContent(pixels.pixel(x: Self.pad - 1, y: Self.pad + 30)))
            try assertSnapshot(image, named: "s2-radius-limited-\(style.rawValue)")
        }
    }

    @Test("[S2-AC7] none / spread / hug × low / medium / high")
    func shadowMatrix() throws {
        let sharp = Border(style: .sharp)
        let none = try render(sharp, Shadow(style: .none))
        let nonePixels = try PixelBuffer(none)
        var shadowed = 0
        for y in 0..<none.height {
            for x in 0..<none.width where !(Self.pad..<(Self.pad + 200) ~= x && Self.pad..<(Self.pad + 120) ~= y) {
                if nonePixels.pixel(x: x, y: y) != Self.backdrop { shadowed += 1 }
            }
        }
        #expect(shadowed == 0, "\(shadowed) shadow pixels with shadow = none")
        try assertSnapshot(none, named: "s2-shadow-none")

        for style in [ShadowStyle.spread, .hug] {
            var darkness: [Double] = []
            for intensity in ShadowIntensity.allCases {
                let image = try render(sharp, Shadow(style: style, intensity: intensity))
                darkness.append(try shadowDarkness(image))
                try assertSnapshot(image, named: "s2-shadow-\(style.rawValue)-\(intensity.rawValue)")
                if style == .hug { try expectHugExtent(image) }
            }
            #expect(darkness[0] > 0 && darkness[0] < darkness[1] && darkness[1] < darkness[2], "\(style): \(darkness)")
        }
    }

    private func expectHugExtent(_ image: CGImage) throws {
        let pixels = try PixelBuffer(image)
        let limit = Int(ShadowMetrics.hugMaxExtent)
        let outside = Self.pad - limit - 1
        var beyond = 0
        for x in stride(from: 0, to: image.width, by: 3) {
            for y in [outside, image.height - 1 - outside] {
                let delta = zip(pixels.pixel(x: x, y: y), Self.backdrop).map { abs(Int($0) - Int($1)) }.max() ?? 0
                if delta > 1 { beyond += 1 }
            }
        }
        #expect(beyond == 0, "hug shadow reaches beyond \(limit) px at \(beyond) sampled points")
    }

    @Test("[S2-AC8] the shadow follows a round 80 px corner (no square shadow in the corner)")
    func shadowFollowsShape() throws {
        let content = try Fixtures.solid(width: 400, height: 300)
        let rounded = try render(
            Border(style: .round, radius: 80), Shadow(style: .hug, intensity: .high), content: content)
        let square = try render(Border(style: .sharp), Shadow(style: .hug, intensity: .high), content: content)
        // Just inside the bounding box at the bottom-left corner: the square shape is content, the round one
        // is backdrop with at most a faint shadow, far lighter than under a straight edge.
        let pixels = try PixelBuffer(rounded)
        let corner = luminance(pixels.pixel(x: Self.pad + 4, y: Self.pad + 300 + 2))
        let edge = luminance(pixels.pixel(x: Self.pad + 200, y: Self.pad + 300 + 2))
        #expect(corner > edge + 10, "corner \(corner) vs edge \(edge)")
        let squareCorner = luminance(try PixelBuffer(square).pixel(x: Self.pad + 4, y: Self.pad + 300 + 2))
        #expect(corner > squareCorner + 10)
        try assertSnapshot(rounded, named: "s2-shadow-round-80")
    }

    @Test("[S2-AC10] a 2× render is the 1× render at twice the resolution (SSIM ≥ 0.98)")
    func scaleInvariance() throws {
        // Solid content isolates the border and shadow structure (resampling detailed content is an S1 concern).
        let content = try Fixtures.solid(width: 200, height: 120)
        let project = Project(shadow: Shadow(style: .spread, intensity: .high))
        let one = try Renderer.render(project: project, content: content, scale: 1)
        let two = try Renderer.render(project: project, content: content, scale: 2)
        #expect((two.width, two.height) == (one.width * 2, one.height * 2))
        let downscaled = try #require(Self.resize(two, width: one.width, height: one.height))
        let ssim = try Self.ssim(PixelBuffer(one), PixelBuffer(downscaled))
        #expect(ssim >= 0.98, "SSIM \(ssim)")
        // The shadow's darkest point sits twice as far below the content at 2×.
        #expect(abs(try shadowRowOffset(two) - 2 * shadowRowOffset(one)) <= 2)
    }

    /// Rows below the content's bottom edge where the shadow is darkest.
    private func shadowRowOffset(_ image: CGImage) throws -> Int {
        let pixels = try PixelBuffer(image)
        let scale = image.width / (200 + 2 * Self.pad)
        let bottom = (Self.pad + 120) * scale
        let x = image.width / 2
        let rows = bottom..<image.height
        let darkest = rows.min { luminance(pixels.pixel(x: x, y: $0)) < luminance(pixels.pixel(x: x, y: $1)) }
        return (darkest ?? bottom) - bottom
    }

    @Test("[S2-AC15] a transparent cut-out casts no shadow from its rectangular bounds")
    func alphaShadow() throws {
        let cutOut = try Fixtures.draw(width: 200, height: 120) { context in
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.8, alpha: 1))
            context.addPath(
                CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: 200, height: 120), cornerWidth: 40, cornerHeight: 40,
                    transform: nil))
            context.fillPath()
        }
        let opaque = try Fixtures.solid(width: 200, height: 120)
        let shadow = Shadow(style: .spread, intensity: .high)
        let alphaShaped = try render(Border(style: .sharp), shadow, content: cutOut)
        let rectangular = try render(Border(style: .sharp), shadow, content: opaque)
        let probe = (x: Self.pad + 3, y: Self.pad + 120 + 3)
        let alphaLuma = luminance(try PixelBuffer(alphaShaped).pixel(x: probe.x, y: probe.y))
        let rectLuma = luminance(try PixelBuffer(rectangular).pixel(x: probe.x, y: probe.y))
        #expect(alphaLuma > rectLuma + 5, "cut-out corner \(alphaLuma) vs rectangle \(rectLuma)")
        // Inside the cut-out the backdrop shows through (lightly shadowed at most), never the content colour.
        #expect(!isContent(try PixelBuffer(alphaShaped).pixel(x: Self.pad + 1, y: Self.pad + 1)))
        try assertSnapshot(alphaShaped, named: "s2-shadow-alpha-cutout")
    }

    // MARK: Helpers

    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = Renderer.makeContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Mean SSIM over 8×8 luminance windows.
    static func ssim(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> Double {
        func luma(_ buffer: PixelBuffer, _ x: Int, _ y: Int) -> Double {
            let p = buffer.pixel(x: x, y: y)
            return 0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2])
        }
        let c1: Double = (0.01 * 255) * (0.01 * 255)
        let c2: Double = (0.03 * 255) * (0.03 * 255)
        var total = 0.0
        var windows = 0
        for wy in stride(from: 0, to: lhs.height - 7, by: 8) {
            for wx in stride(from: 0, to: lhs.width - 7, by: 8) {
                var a: [Double] = []
                var b: [Double] = []
                for y in wy..<(wy + 8) {
                    for x in wx..<(wx + 8) {
                        a.append(luma(lhs, x, y))
                        b.append(luma(rhs, x, y))
                    }
                }
                let n = Double(a.count)
                let ma = a.reduce(0, +) / n
                let mb = b.reduce(0, +) / n
                let va = a.map { ($0 - ma) * ($0 - ma) }.reduce(0, +) / n
                let vb = b.map { ($0 - mb) * ($0 - mb) }.reduce(0, +) / n
                let cov = zip(a, b).map { ($0 - ma) * ($1 - mb) }.reduce(0, +) / n
                total += ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
                windows += 1
            }
        }
        return windows == 0 ? 1 : total / Double(windows)
    }
}
