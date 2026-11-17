import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S8 effect rendering. Pixel checks use a top-left origin; content is 120×60 at padding 64 (canvas 248×188).
@Suite("Backdrop effects rendering")
struct EffectsRenderTests {
    static let pad = 64
    static let gradient = BackdropFixtures.gradient((0, 0x2E6BE6), (1, 0xF2A33A), angle: 135)

    static func project(
        _ backdrop: Backdrop = .gradient(gradient), _ edit: (inout BackdropEffects) -> Void
    )
        -> Project
    {
        var project = Project.plain(backdrop: backdrop)
        edit(&project.backdropSettings.effects)
        return project
    }

    static func render(_ project: Project, scale: Double = 1, content: CGImage? = nil) throws -> CGImage {
        try Renderer.render(
            project: project, content: content ?? Fixtures.solid(width: 120, height: 60), scale: scale)
    }

    static func luma(_ p: [UInt8]) -> Double { 0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2]) }

    /// Indices of pixels that differ between two same-size buffers.
    static func differing(_ lhs: PixelBuffer, _ rhs: PixelBuffer) -> [(x: Int, y: Int)] {
        var result: [(Int, Int)] = []
        for y in 0..<lhs.height {
            for x in 0..<lhs.width where lhs.pixel(x: x, y: y) != rhs.pixel(x: x, y: y) { result.append((x, y)) }
        }
        return result
    }

    static func isContent(_ x: Int, _ y: Int) -> Bool { (pad..<pad + 120).contains(x) && (pad..<pad + 60).contains(y) }

    @Test("[S8-AC1] default effects change nothing: identical to a render without the effects path")
    func defaultsAreIdentity() throws {
        #expect(BackdropEffects().isIdentity)
        #expect(Project().backdropSettings.effects == BackdropEffects())
        // Every existing snapshot still passes; here the effects path with zero-strength settings is also a no-op.
        let plain = try PixelBuffer(Self.render(Self.project { _ in }))
        let zero = try PixelBuffer(
            Self.render(
                Self.project {
                    $0.pattern = BackdropPattern(kind: .dots, intensity: 0)
                    $0.vignette = Vignette(style: .dark, intensity: 0)
                    $0.overlay = OverlayTexture(kind: .leaves, opacity: 0)
                }))
        #expect(plain.bytes == zero.bytes)
    }

    @Test("[S8-AC3] blur, noise, saturation and opacity change backdrop pixels only, never the content")
    func adjustmentsBackdropOnly() throws {
        let content = try BackdropFixtures.quadrants(width: 120, height: 60)
        let image = try BackdropFixtures.asset(BackdropFixtures.quadrants(width: 248, height: 188), id: "bg")
        let plain = Project.plain(backdrop: .image(.file(image.reference)))
        var adjusted = plain
        adjusted.backdropSettings.effects.adjustments = BackdropAdjustments(
            blur: 8, noise: 0.5, saturation: 0.4, opacity: 1)
        let media = [image.reference.id: image]
        let before = try PixelBuffer(Renderer.render(project: plain, content: content, media: media))
        let afterImage = try Renderer.render(project: adjusted, content: content, media: media)
        let after = try PixelBuffer(afterImage)
        let changed = Self.differing(before, after)
        #expect(changed.count > before.width * before.height / 4)
        #expect(!changed.contains { Self.isContent($0.x, $0.y) }, "content pixels changed")
        try assertSnapshot(afterImage, named: "s8-adjustments")
    }

    @Test("[S8-AC4] blur softens hard backdrop edges, looks the same at 4×, and leaves a solid colour alone")
    func blur() throws {
        let image = try BackdropFixtures.asset(BackdropFixtures.quadrants(width: 248, height: 188), id: "bg")
        var project = Project.plain(backdrop: .image(.file(image.reference)))
        project.backdropSettings.effects.adjustments.blur = 12
        let media = [image.reference.id: image]
        let content = try Fixtures.solid(width: 120, height: 60)
        let one = try Renderer.render(project: project, content: content, media: media)
        let pixels = try PixelBuffer(one)
        // Along row 20 the backdrop jumps red → green at x = 124: count the pixels in transition.
        let left = BackdropFixtures.topLeft
        let right = BackdropFixtures.topRight
        let transition = (0..<248).filter { x in
            let p = pixels.pixel(x: x, y: 20)
            return !BackdropFixtures.close(p, left, tolerance: 6) && !BackdropFixtures.close(p, right, tolerance: 6)
        }
        #expect(transition.count >= 12, "edge transition \(transition.count) px")
        let four = try Renderer.render(project: project, content: content, media: media, scale: 4)
        let downscaled = try #require(BorderShadowRenderTests.resize(four, width: one.width, height: one.height))
        let ssim = BorderShadowRenderTests.ssim(pixels, try PixelBuffer(downscaled))
        #expect(ssim >= 0.97, "SSIM \(ssim)")
        let solid = Project.plain(backdrop: .solid(RGBAColor(rgb: 0x3366AA)))
        var blurred = solid
        blurred.backdropSettings.effects.adjustments.blur = 30
        #expect(try PixelBuffer(Self.render(solid)).bytes == PixelBuffer(Self.render(blurred)).bytes)
        try assertSnapshot(one, named: "s8-blur-12")
    }

    @Test("[S8-AC5] grain is deterministic, per canvas pixel, mean-preserving and scales with the render")
    func noise() throws {
        let color = RGBAColor(rgb: 0x808080)
        let project = Self.project(.solid(color)) { $0.adjustments.noise = 0.6 }
        let first = try Self.render(project)
        #expect(try PixelBuffer(first).bytes == PixelBuffer(Self.render(project)).bytes)
        let pixels = try PixelBuffer(first)
        let samples = (0..<60).flatMap { y in (0..<60).map { x in Double(pixels.pixel(x: x, y: y)[0]) } }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(samples.count)
        #expect(abs(mean - 128) <= 2, "mean \(mean)")
        #expect(variance > 50, "variance \(variance)")
        // At 4× each grain cell is a 4×4 block (± 1 level of dither).
        let four = try PixelBuffer(Self.render(project, scale: 4))
        for cell in [(3, 5), (10, 2), (30, 40)] {
            let reference = Int(four.pixel(x: cell.0 * 4, y: cell.1 * 4)[0])
            for dy in 0..<4 {
                for dx in 0..<4 {
                    #expect(abs(Int(four.pixel(x: cell.0 * 4 + dx, y: cell.1 * 4 + dy)[0]) - reference) <= 1)
                }
            }
        }
        let none = Self.project(.solid(color)) { $0.adjustments.noise = 0 }
        #expect(
            try PixelBuffer(Self.render(none)).bytes == PixelBuffer(Self.render(.plain(backdrop: .solid(color)))).bytes)
    }

    @Test("[S8-AC6] saturation 0 is grey, 200 % adds chroma; opacity halves alpha, checkerboard in preview only")
    func saturationAndOpacity() throws {
        let grey = try PixelBuffer(Self.render(Self.project { $0.adjustments.saturation = 0 }))
        for (x, y) in [(5, 5), (240, 180), (20, 170)] {
            let p = grey.pixel(x: x, y: y)
            #expect(abs(Int(p[0]) - Int(p[1])) <= 1 && abs(Int(p[1]) - Int(p[2])) <= 1, "\(p)")
        }
        func chroma(_ p: [UInt8]) -> Int { Int(p.prefix(3).max() ?? 0) - Int(p.prefix(3).min() ?? 0) }
        let normal = try PixelBuffer(Self.render(Self.project { _ in }))
        let vivid = try PixelBuffer(Self.render(Self.project { $0.adjustments.saturation = 2 }))
        #expect(chroma(vivid.pixel(x: 5, y: 5)) > chroma(normal.pixel(x: 5, y: 5)) + 20)

        let half = Self.project(.solid(RGBAColor(rgb: 0x3366AA))) { $0.adjustments.opacity = 0.5 }
        var session = EditorSession(document: EditorDocument(project: half))
        session.setContent(try Fixtures.solid(width: 120, height: 60))
        let export = try PixelBuffer(ImageCodec.decode(session.exportPNG()))
        #expect(abs(Int(export.pixel(x: 5, y: 5)[3]) - 128) <= 1)
        let grid = TransparencyGrid(light: RGBAColor(rgb: 0xFFFFFF), dark: RGBAColor(rgb: 0x000000))
        let preview = try PixelBuffer(
            #require(try Renderer.render(document: session.document, showsTransparencyGrid: true, grid: grid)))
        // Square (0,0) is the dark one: the preview shows it through the 50 % backdrop; (16,0) is light.
        #expect(preview.pixel(x: 2, y: 2)[3] == 255 && preview.pixel(x: 18, y: 2)[3] == 255)
        #expect(Int(preview.pixel(x: 18, y: 2)[0]) > Int(preview.pixel(x: 2, y: 2)[0]) + 60)
        #expect(BackdropFixtures.close(export.pixel(x: 2, y: 2), export.pixel(x: 18, y: 2), tolerance: 1), "no grid")
    }

    @Test(
        "[S8-AC7] eight pattern options; every pattern differs from the others and from none",
        arguments: [
            PatternKind.circles, .waves, .dots, .rays, .grid, .stripes, .noise,
        ])
    func patterns(kind: PatternKind) throws {
        #expect(PatternKind.allCases == [.none, .circles, .waves, .dots, .rays, .grid, .stripes, .noise])
        let image = try Self.render(
            Self.project(.solid(RGBAColor(rgb: 0xEDEDF2))) { $0.pattern = BackdropPattern(kind: kind, intensity: 0.6) })
        let pixels = try PixelBuffer(image)
        let others = try PatternKind.allCases.filter { $0 != kind }.map { other in
            try PixelBuffer(
                Self.render(
                    Self.project(.solid(RGBAColor(rgb: 0xEDEDF2))) {
                        $0.pattern = BackdropPattern(kind: other, intensity: 0.6)
                    }))
        }
        for other in others {
            #expect(Self.differing(pixels, other).count > 500, "\(kind) looks like another pattern")
        }
        try assertSnapshot(image, named: "s8-pattern-\(kind.rawValue)")
    }

    @Test("[S8-AC8] intensity 0 changes nothing, thicker covers more, pixels take the pattern colour")
    func patternParameters() throws {
        let base = RGBAColor(rgb: 0xEDEDF2)
        /// Total darkening (sum of red-channel drops) caused by the pattern.
        func coverage(_ thickness: Double) throws -> Int {
            let pixels = try PixelBuffer(
                Self.render(
                    Self.project(.solid(base)) { $0.pattern = BackdropPattern(kind: .grid, thickness: thickness) }))
            let plain = try PixelBuffer(Self.render(.plain(backdrop: .solid(base))))
            return stride(from: 0, to: pixels.bytes.count, by: 4).reduce(0) {
                $0 + abs(Int(plain.bytes[$1]) - Int(pixels.bytes[$1]))
            }
        }
        #expect(try coverage(2) > coverage(1) * 3 / 2)
        let off = try PixelBuffer(
            Self.render(Self.project(.solid(base)) { $0.pattern = BackdropPattern(kind: .grid, intensity: 0) }))
        #expect(off.bytes == (try PixelBuffer(Self.render(.plain(backdrop: .solid(base))))).bytes)
        let red = RGBAColor(rgb: 0xFF0000)
        let tinted = try PixelBuffer(
            Self.render(
                Self.project(.solid(base)) {
                    $0.pattern = BackdropPattern(kind: .stripes, intensity: 1, thickness: 3, color: red)
                }))
        let reds = stride(from: 0, to: tinted.bytes.count, by: 4).filter {
            Array(tinted.bytes[$0..<$0 + 4]) == [255, 0, 0, 255]
        }
        #expect(reds.count > 1000, "\(reds.count) pure pattern-colour pixels")
    }

    @Test("[S8-AC9] dark vignette darkens corners, light lightens them; spread reaches further; snapshots")
    func vignette() throws {
        let base = RGBAColor(rgb: 0x8090A0)
        func render(_ vignette: Vignette) throws -> CGImage {
            try Self.render(Self.project(.solid(base)) { $0.vignette = vignette })
        }
        let plain = try PixelBuffer(render(Vignette()))
        let dark = try render(Vignette(style: .dark))
        let light = try render(Vignette(style: .light))
        let darkPixels = try PixelBuffer(dark)
        #expect(Self.luma(darkPixels.pixel(x: 1, y: 1)) < Self.luma(plain.pixel(x: 1, y: 1)) - 30)
        #expect(darkPixels.pixel(x: 124, y: 30) == plain.pixel(x: 124, y: 30), "the centre is unchanged")
        #expect(Self.luma(try PixelBuffer(light).pixel(x: 1, y: 1)) > Self.luma(plain.pixel(x: 1, y: 1)) + 30)
        let narrow = try PixelBuffer(render(Vignette(style: .dark, spread: 0.2)))
        let wide = try PixelBuffer(render(Vignette(style: .dark, spread: 0.9)))
        #expect(Self.differing(plain, wide).count > Self.differing(plain, narrow).count + 2000)
        #expect(try PixelBuffer(render(Vignette(style: .dark, intensity: 0))).bytes == plain.bytes)
        try assertSnapshot(dark, named: "s8-vignette-dark")
        try assertSnapshot(light, named: "s8-vignette-light")
    }

    @Test(
        "[S8-AC10] six procedural overlay textures, all different",
        arguments: [
            OverlayKind.blinds, .window, .leaves, .lattice, .ripples, .dapple,
        ])
    func overlays(kind: OverlayKind) throws {
        #expect(OverlayKind.allCases == [.none, .blinds, .window, .leaves, .lattice, .ripples, .dapple])
        func render(_ kind: OverlayKind) throws -> CGImage {
            try Self.render(Self.project { $0.overlay = OverlayTexture(kind: kind, opacity: 0.5) })
        }
        let image = try render(kind)
        let pixels = try PixelBuffer(image)
        for other in OverlayKind.allCases where other != kind {
            #expect(Self.differing(pixels, try PixelBuffer(render(other))).count > 1000, "\(kind) vs \(other)")
        }
        try assertSnapshot(image, named: "s8-overlay-\(kind.rawValue)")
    }

    @Test("[S8-AC11] overlay above shades the content; below leaves the content alone; opacity 0 does nothing")
    func overlayPosition() throws {
        let plain = try PixelBuffer(Self.render(Self.project { _ in }))
        func render(_ position: OverlayPosition, opacity: Double = 0.6) throws -> PixelBuffer {
            try PixelBuffer(
                Self.render(
                    Self.project { $0.overlay = OverlayTexture(kind: .blinds, opacity: opacity, position: position) }))
        }
        let above = Self.differing(plain, try render(.above))
        let below = Self.differing(plain, try render(.below))
        #expect(above.contains { Self.isContent($0.x, $0.y) })
        #expect(!below.isEmpty && !below.contains { Self.isContent($0.x, $0.y) })
        #expect(try render(.above, opacity: 0).bytes == plain.bytes)
    }

    @Test("[S8-AC12] with every effect on, preview and export are byte-identical at 1× and 2×; 2× ≈ 1×")
    func parity() throws {
        let project = Self.project {
            $0.adjustments = BackdropAdjustments(blur: 6, noise: 0.15, saturation: 1.4, opacity: 0.9)
            $0.pattern = BackdropPattern(kind: .dots, intensity: 0.4)
            $0.vignette = Vignette(style: .dark)
            $0.overlay = OverlayTexture(kind: .window)
        }
        var session = EditorSession(document: EditorDocument(project: project))
        session.setContent(try Fixtures.solid(width: 120, height: 60))
        var renders: [CGImage] = []
        for scale in [1.0, 2.0] {
            let preview = try #require(try Renderer.render(document: session.document, scale: scale))
            #expect(try session.exportPNG(scale: scale) == ImageCodec.pngData(preview))
            renders.append(preview)
        }
        let downscaled = try #require(
            BorderShadowRenderTests.resize(renders[1], width: renders[0].width, height: renders[0].height))
        let ssim = BorderShadowRenderTests.ssim(try PixelBuffer(renders[0]), try PixelBuffer(downscaled))
        #expect(ssim >= 0.97, "SSIM \(ssim)")
        try assertSnapshot(renders[0], named: "s8-all-effects")
    }
}
