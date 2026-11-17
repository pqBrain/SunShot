import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Performance budgets. Only enforced when `SUNSHOT_PERF=1` (the gate runs these in release mode).
@Suite("Render performance", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct RenderPerformanceTests {
    @Test("[S1-AC18] 3712×2032 content → 3840×2160 canvas renders in ≤ 500 ms (median of 10, release)")
    func fourKExport() throws {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 3712, height: 2032))
        let document = session.document
        let first = try #require(try Renderer.render(document: document))  // warm-up
        #expect((first.width, first.height) == (3840, 2160))
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<10 {
            samples.append(try clock.measure { _ = try Renderer.render(document: document) })
        }
        let median = samples.sorted()[samples.count / 2]
        let milliseconds = median.components.seconds * 1000 + median.components.attoseconds / 1_000_000_000_000_000
        print("perf.render4k.median_ms=\(milliseconds)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }
}
