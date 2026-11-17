import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

/// S6 thumbnail latency budget. The name contains `RenderPerformanceTests`, so the gate's perf stage
/// (`SUNSHOT_PERF=1`, release, serial) picks it up; normal test runs skip it.
@MainActor
@Suite("Layout thumbnail latency", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct LayoutThumbnailRenderPerformanceTests {
    @Test("[S6-AC14] thumbnails regenerate within 300 ms of a style change, debounce included (release)")
    func styleChangeLatency() async throws {
        let model = EditorModel()
        model.layout.reduceMotion = { false }
        await model.importData(try TestImages.png(width: 1440, height: 900), fileName: "shot.png")
        try #require(model.hasContent)
        await model.layout.thumbnailTask?.value
        try #require(!model.layout.thumbnails.isEmpty)

        var samples: [Duration] = []
        let clock = ContinuousClock()
        for radius in [4.0, 12, 20, 28, 36] {
            let start = clock.now
            await model.perform { $0.setCornerRadius(radius) }.value
            await model.layout.thumbnailTask?.value
            samples.append(clock.now - start)
        }
        let median = samples.sorted()[samples.count / 2]
        let milliseconds = median.components.seconds * 1000 + median.components.attoseconds / 1_000_000_000_000_000
        print("perf.layout_thumbnail_latency_ms=\(milliseconds)")
        #expect(median <= .milliseconds(300), "median \(median)")
    }
}
