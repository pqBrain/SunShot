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

@Suite("Large renders", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct LargeRenderTests {
    @Test("[S2-AC17] 4K canvas with border and shadow renders in ≤ 500 ms (median of 10, release)")
    func fourKStyled() throws {
        let project = Project(
            border: Border(style: .smooth, radius: 60), shadow: Shadow(style: .spread, intensity: .high))
        let content = try SampleContent.image(width: 3712, height: 2032)
        _ = try Renderer.render(project: project, content: content)
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(project: project, content: content) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_styled.median=\(median)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S2-AC17] 8000×8000 with spread/high and radius 200 → 8128×8128, ≤ 1.5 GB growth, shadow not clipped")
    func hugeStyled() throws {
        let content = try SampleContent.image(width: 8000, height: 8000)
        let project = Project(
            border: Border(style: .smooth, radius: 200), shadow: Shadow(style: .spread, intensity: .high))
        let before = MemoryProbe.footprint()
        let image = try Renderer.render(project: project, content: content)
        let peak = MemoryProbe.peakFootprint()
        #expect((image.width, image.height) == (8128, 8128))
        let growth = Double(peak - min(before, peak)) / 1_073_741_824
        print("perf.render8k_styled.peak_growth_gb=\(growth)")
        #expect(growth <= 1.5, "peak growth \(growth) GB")
        // The outermost rows/columns are plain backdrop: the shadow fades out inside the padding.
        for rect in [
            CGRect(x: 0, y: 8127, width: 8128, height: 1), CGRect(x: 0, y: 0, width: 1, height: 8128),
            CGRect(x: 8127, y: 0, width: 1, height: 8128),
        ] {
            let strip = try PixelBuffer(#require(image.cropping(to: rect)))
            let clipped = stride(from: 0, to: strip.bytes.count, by: 4).filter {
                Array(strip.bytes[$0..<$0 + 4]) != [237, 237, 242, 255]
            }
            #expect(clipped.isEmpty, "\(clipped.count) non-backdrop pixels on the canvas edge \(rect)")
        }
    }
}

enum MemoryProbe {
    private static func info() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    static func footprint() -> UInt64 { info()?.phys_footprint ?? 0 }
    static func peakFootprint() -> UInt64 { info()?.ledger_phys_footprint_peak.magnitude ?? 0 }
}
