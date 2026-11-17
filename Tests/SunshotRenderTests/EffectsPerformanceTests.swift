import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S8 budgets. An extension of `RenderPerformanceTests`, so they only run with `SUNSHOT_PERF=1` (release perf stage).
extension RenderPerformanceTests {
    static func allEffects(blur: Double = 24) -> BackdropEffects {
        BackdropEffects(
            adjustments: BackdropAdjustments(blur: blur, noise: 0.3, saturation: 1.3, opacity: 0.95),
            pattern: BackdropPattern(kind: .waves, intensity: 0.4),
            vignette: Vignette(style: .dark),
            overlay: OverlayTexture(kind: .leaves))
    }

    @Test("[S8-AC13] 4K with an image backdrop and every effect on renders in ≤ 500 ms (median of 10)")
    func fourKAllEffects() throws {
        let backdropImage = try SampleContent.image(width: 4000, height: 3000)
        let reference = MediaReference(id: "bg", fileName: nil, pixelSize: PixelSize(width: 4000, height: 3000))
        let media = ["bg": MediaAsset(reference: reference, data: Data(), image: backdropImage)]
        var project = Project(backdrop: .image(.file(reference)))
        project.backdropSettings.effects = Self.allEffects()
        let content = try SampleContent.image(width: 3712, height: 2032)
        let first = try Renderer.render(project: project, content: content, media: media)
        #expect((first.width, first.height) == (3840, 2160))
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(project: project, content: content, media: media) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_all_effects.median=\(median)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S8-AC12] every effect on: preview equals export at 4K, and 4K downscaled ≈ 1× (SSIM ≥ 0.97)")
    func fourKEffectsParity() throws {
        var project = Project(backdrop: .gradient(SunshotDefaults.gradient))
        project.backdropSettings.effects = Self.allEffects(blur: 8)
        project.backdropSettings.effects.adjustments.noise = 0.1
        var session = EditorSession(document: EditorDocument(project: project))
        session.setContent(try Fixtures.solid(width: 1600, height: 1000))
        let one = try #require(try session.render(scale: 1))
        let scale = 3840 / Double(one.width)
        let fourK = try #require(try session.render(scale: scale))
        #expect(try session.exportPNG(scale: scale) == ImageCodec.pngData(fourK))
        let downscaled = try #require(BorderShadowRenderTests.resize(fourK, width: one.width, height: one.height))
        let ssim = BorderShadowRenderTests.ssim(try PixelBuffer(one), try PixelBuffer(downscaled))
        print("perf.effects.ssim_4k_vs_1x=\(ssim)")
        #expect(ssim >= 0.97, "SSIM \(ssim)")
    }
}
