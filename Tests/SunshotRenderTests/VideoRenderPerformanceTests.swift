import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Records the memory footprint after each exported frame.
final class FootprintTrace: @unchecked Sendable {
    // SAFETY: `samples` is only touched while `lock` is held.
    private let lock = NSLock()
    private var samples: [UInt64] = []

    func sample() {
        let now = MemoryProbe.footprint()
        lock.lock()
        samples.append(now)
        lock.unlock()
    }

    var values: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

/// S13 budgets. Only enforced when `SUNSHOT_PERF=1` (the gate runs these in release mode, serially).
@Suite("Video render performance", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct VideoRenderPerformanceTests {
    @Test("[S13-AC15] a 6 s 1080p 60 fps export (≈ 2.7 GB of frames) never grows the footprint by more than 768 MB")
    func boundedMemory() async throws {
        var project = Project(shadow: Shadow(style: .spread, intensity: .high))
        project.backdrop = .gradient(SunshotDefaults.gradient)
        project.timeline = AnimationTimeline(
            clips: [
                AnimationClip(target: ContentTransform(zoom: 130, rotation: 8, tiltX: 20), durationMS: 2500),
                AnimationClip(target: ContentTransform(x: -0.1, zoom: 90), durationMS: 2500),
            ],
            leadInMS: 0)
        project.timeline.video = VideoExportOptions(resolution: .hd, frameRate: .fps60)
        let document = EditorDocument(
            project: project, content: ContentImage(try SampleContent.image(width: 1600, height: 1000)))
        let plan = try #require(AnimationRenderer.exportPlan(for: document))
        #expect(plan.frameCount == 360)
        let url = try VideoFixtures.url("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let before = MemoryProbe.footprint()
        let trace = FootprintTrace()
        let elapsed = try await ContinuousClock().measure {
            try await VideoExporter.export(document, to: url) { _ in trace.sample() }
        }
        let samples = trace.values
        // Signed: earlier tests in the serial perf run may release memory during this one.
        func megabytes(_ value: UInt64) -> Int { Int((Int64(value) - Int64(before)) / 1_048_576) }
        let firstHalf = megabytes(samples.prefix(samples.count / 2).max() ?? before)
        let overall = megabytes(samples.max() ?? before)
        let last = megabytes(samples.last ?? before)
        print(
            "perf.video.export_1080p60_6s_ms=\(elapsed.components.seconds * 1000) "
                + "perf.video.first_half_mb=\(firstHalf) perf.video.peak_mb=\(overall) perf.video.end_mb=\(last)")
        #expect(overall <= 768, "grew \(overall) MB")
    }
}
