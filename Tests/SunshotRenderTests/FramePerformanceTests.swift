import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S5 budgets. An extension of `RenderPerformanceTests`, so they only run with `SUNSHOT_PERF=1` (release, serial).
extension RenderPerformanceTests {
    @Test("[S5-AC18] browser frame + high shadow + gradient: preview == export at 1×, 2×, 4K; 4K ≤ 500 ms median")
    func framedParityAndBudget() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 1600, height: 1000))
        session.setShadowIntensity(.high)
        session.setBackdropKind(.gradient)
        session.setFrameKind(.browserWindow)
        session.setFrameTitle("sunshot.app/release-notes")
        for scale in [ExportScale.x1, .x2, .k4] {
            session.setExportScale(scale)
            let plan = try #require(session.exportPlan)
            let preview = try #require(
                try Renderer.render(document: session.document, scale: plan.renderScale, showsTransparencyGrid: true))
            #expect(try session.exportImageData() == ImageCodec.pngData(preview), "\(scale)")
        }
        let plan = try #require(session.exportPlan)
        let document = session.document
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(document: document, scale: plan.renderScale) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_framed.median=\(median)")
        #expect(max(plan.width, plan.height) == 3840)
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S5-AC17] 8000×8000 with a mac window frame exports 8128×8156 at 1× with ≤ 1.5 GB peak growth")
    func hugeFramed() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 8000, height: 8000))
        session.setFrameKind(.macWindow)
        session.setExportScale(.x1)
        let before = MemoryProbe.footprint()
        let data = try session.exportImageData()
        let peak = MemoryProbe.peakFootprint()
        let image = try ImageCodec.decode(data)
        #expect((image.width, image.height) == (8128, 8156))
        let growth = Double(peak - min(before, peak)) / 1_073_741_824
        print("perf.export8k_framed.peak_growth_gb=\(growth)")
        #expect(growth <= 1.5, "peak growth \(growth) GB")
    }
}
