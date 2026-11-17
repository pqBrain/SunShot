import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S4 export budgets and full-scale parity. An extension of `RenderPerformanceTests`, so they only run with
/// `SUNSHOT_PERF=1` in the release-mode perf stage (the gradient fill alone is ~13 s at 6K in a debug build).
extension RenderPerformanceTests {
    private static func milliseconds(_ duration: Duration) -> Int64 {
        duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
    }

    @Test("[S4-AC13] export equals the preview render at 1×, 2×, 4K and 6K; 4K downscaled ≈ 1× (SSIM ≥ 0.98)")
    func exportParity() throws {
        var session = EditorSession()
        // Solid content isolates the styling (resampling detailed content is an S1 concern).
        session.setContent(try Fixtures.solid(width: 1600, height: 1000))
        session.setCornerRadius(24)
        session.setShadowIntensity(.high)
        session.setBackdropKind(.gradient)
        var renders: [ExportScale: CGImage] = [:]
        for scale in ExportScale.allCases {
            session.setExportScale(scale)
            let plan = try #require(session.exportPlan)
            let preview = try #require(try Renderer.render(document: session.document, scale: plan.renderScale))
            #expect((preview.width, preview.height) == (plan.width, plan.height))
            #expect(try session.exportImageData() == ImageCodec.pngData(preview), "\(scale)")
            renders[scale] = preview
        }
        let one = try #require(renders[.x1])
        let fourK = try #require(renders[.k4])
        let downscaled = try #require(BorderShadowRenderTests.resize(fourK, width: one.width, height: one.height))
        let ssim = try BorderShadowRenderTests.ssim(PixelBuffer(one), PixelBuffer(downscaled))
        print("perf.parity.ssim_4k_vs_1x=\(ssim)")
        #expect(ssim >= 0.98, "SSIM \(ssim)")
    }

    @Test("[S4-AC19] 3712×2032 on Auto at 4K renders in ≤ 500 ms (median of 10, excluding encoding)")
    func fourKScaleRender() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 3712, height: 2032))
        session.setExportScale(.k4)
        let plan = try #require(session.exportPlan)
        #expect(plan.outputSize == PixelSize(width: 3840, height: 2160))
        _ = try session.render(scale: plan.renderScale)
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in try clock.measure { _ = try session.render(scale: plan.renderScale) } }
        let median = samples.sorted()[5]
        print("perf.export4k_render.median_ms=\(Self.milliseconds(median))")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S4] 6K PNG export (render + encode) of 3712×2032 content stays within budget (median of 3)")
    func sixKExport() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 3712, height: 2032))
        session.setExportScale(.k6)
        #expect(session.exportPlan?.outputSize == PixelSize(width: 6144, height: 3456))
        _ = try session.exportImageData()
        let clock = ContinuousClock()
        let samples = try (0..<3).map { _ in try clock.measure { _ = try session.exportImageData() } }
        let median = samples.sorted()[1]
        print("perf.export6k_png.median_ms=\(Self.milliseconds(median))")
        #expect(median <= .milliseconds(Self.sixKBudgetMilliseconds), "median \(median)")
    }

    /// Measured 356–395 ms on the reference Mac (see DECISIONS.md); the budget leaves headroom.
    static let sixKBudgetMilliseconds: Int64 = 1000

    @Test("[S4-AC19] 8000×8000 export at 1× stays ≤ 1.5 GB; at 2× (16256²) completes ≤ 4 GB or is refused")
    func hugeExports() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 8000, height: 8000))
        session.setExportScale(.x1)
        var before = MemoryProbe.footprint()
        let one = try session.exportImageData()
        var growth = Double(MemoryProbe.peakFootprint() - min(before, MemoryProbe.peakFootprint())) / 1_073_741_824
        print("perf.export8k_1x.peak_growth_gb=\(growth)")
        #expect(!one.isEmpty)
        #expect(growth <= 1.5, "1× peak growth \(growth) GB")

        session.setExportScale(.x2)
        #expect(session.exportPlan?.outputSize == PixelSize(width: 16256, height: 16256))
        before = MemoryProbe.footprint()
        do {
            let two = try session.exportImageData()
            growth = Double(MemoryProbe.peakFootprint() - min(before, MemoryProbe.peakFootprint())) / 1_073_741_824
            print("perf.export8k_2x.peak_growth_gb=\(growth) bytes=\(two.count)")
            #expect(growth <= 4, "2× peak growth \(growth) GB")
        } catch ExportError.tooLarge {
            print("perf.export8k_2x.refused")
        }
    }
}
