import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S6 budgets. Only enforced when `SUNSHOT_PERF=1` (the gate runs these in release mode, serially).
@Suite("Transform render performance", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct TransformRenderPerformanceTests {
    static func milliseconds(_ duration: Duration) -> Int64 {
        duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
    }

    @Test("[S6-AC20] 4K canvas with tilt, rotation, border and shadow renders in ≤ 500 ms (median of 10)")
    func fourKTilted() throws {
        var project = Project(
            border: Border(style: .smooth, radius: 60), shadow: Shadow(style: .spread, intensity: .high))
        project.placement.transform = ContentTransform(x: 0.05, zoom: 90, rotation: -6, tiltX: 18, tiltY: -24)
        let content = try SampleContent.image(width: 3712, height: 2032)
        let first = try Renderer.render(project: project, content: content)
        #expect((first.width, first.height) == (3840, 2160))
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(project: project, content: content) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_tilted.median_ms=\(Self.milliseconds(median))")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S6-AC20] all preset thumbnails (≥ 12 at 200 px) render in ≤ 600 ms in total")
    func thumbnails() throws {
        let presets = try LayoutPresetCatalog.load().presets
        #expect(presets.count >= 12)
        var project = Project(shadow: Shadow(style: .spread, intensity: .high))
        project.backdrop = .gradient(SunshotDefaults.gradient)
        let document = EditorDocument(
            project: project, content: ContentImage(try SampleContent.image(width: 2880, height: 1800)))
        _ = try LayoutThumbnails.render(document: document, presets: presets)
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try LayoutThumbnails.render(document: document, presets: presets) }
        print("perf.layout_thumbnails_ms=\(Self.milliseconds(elapsed))")
        #expect(elapsed <= .milliseconds(600), "\(elapsed)")
    }

    @Test("[S6-AC10] tilted 4K export equals the preview render and is structurally the 1× render (SSIM ≥ 0.98)")
    func fourKParity() throws {
        let document = try TransformRenderTests.parityDocument()
        let one = try #require(try Renderer.render(document: document, scale: 1))
        let scale = ExportScale.k4.factor(for: PixelSize(width: one.width, height: one.height))
        let preview = try #require(try Renderer.render(document: document, scale: scale))
        let export = try #require(try Renderer.render(document: document, scale: scale))
        #expect(try PixelBuffer(preview).bytes == PixelBuffer(export).bytes)
        let downscaled = try #require(BorderShadowRenderTests.resize(export, width: one.width, height: one.height))
        let ssim = BorderShadowRenderTests.ssim(try PixelBuffer(one), try PixelBuffer(downscaled))
        print("perf.tilt_4k_ssim=\(ssim)")
        #expect(ssim >= 0.98, "SSIM \(ssim)")
    }

    @Test("[S6-AC11] 8000×8000 content, tilt 60/60, zoom 400 %, rotation 180° renders in ≤ 2 s")
    func extreme() throws {
        var project = Project.plain()
        project.placement.transform = ContentTransform(zoom: 400, rotation: 180, tiltX: 60, tiltY: 60)
        let content = try SampleContent.image(width: 8000, height: 8000)
        let clock = ContinuousClock()
        var image: CGImage?
        let elapsed = try clock.measure { image = try Renderer.render(project: project, content: content) }
        print("perf.extreme_transform_ms=\(Self.milliseconds(elapsed))")
        let rendered = try #require(image)
        #expect((rendered.width, rendered.height) == (8128, 8128))
        #expect(elapsed <= .seconds(2), "\(elapsed)")
    }
}
