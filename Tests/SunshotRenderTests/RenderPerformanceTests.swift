import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Performance budgets. Only enforced when `SUNSHOT_PERF=1` (the gate runs these in release mode).
@Suite("Render performance", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct RenderPerformanceTests {
    @Test("[S0] 4K export renders within 500 ms budget")
    func fourKExport() throws {
        let content = try SampleContent.image(width: 3456, height: 2234)
        let project = Project(canvas: .exact(PixelSize(width: 3840, height: 2160)))
        _ = try Renderer.render(project: project, content: content)  // warm-up
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<5 {
            samples.append(try clock.measure { _ = try Renderer.render(project: project, content: content) })
        }
        let median = samples.sorted()[samples.count / 2]
        print(
            "perf.render4k.median_ms=\(median.components.attoseconds / 1_000_000_000_000_000 + median.components.seconds * 1000)"
        )
        #expect(median < .milliseconds(500), "median \(median)")
    }
}
