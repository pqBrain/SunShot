import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// Image-backdrop budgets. Only enforced when `SUNSHOT_PERF=1` (the gate runs these in release mode).
@Suite("Backdrop performance", .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct BackdropPerformanceTests {
    /// A decoded image as stored by an import (the bytes are irrelevant to rendering).
    private func asset(width: Int, height: Int) throws -> MediaAsset {
        let image = try SampleContent.image(width: width, height: height)
        let reference = MediaReference(
            id: "large", fileName: "large.png", pixelSize: PixelSize(width: width, height: height))
        return MediaAsset(reference: reference, data: Data(), image: image)
    }

    @Test("[S3-AC19] 3840×2160 canvas with a 4000×3000 image backdrop renders in ≤ 500 ms (median of 10, release)")
    func fourKImageBackdrop() throws {
        let backdrop = try asset(width: 4000, height: 3000)
        let project = Project(backdrop: .image(.file(backdrop.reference)))
        let content = try SampleContent.image(width: 3712, height: 2032)
        let media = [backdrop.reference.id: backdrop]
        let first = try Renderer.render(project: project, content: content, media: media)  // warm-up
        #expect((first.width, first.height) == (3840, 2160))
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(project: project, content: content, media: media) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_image_backdrop.median=\(median)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S3-AC19] 8000×8000 image backdrop + 8000×8000 content exports with ≤ 2 GB peak growth")
    func hugeImageBackdrop() throws {
        let backdrop = try asset(width: 8000, height: 8000)
        let content = try SampleContent.image(width: 8000, height: 8000)
        let project = Project(backdrop: .image(.file(backdrop.reference)))
        let before = MemoryProbe.footprint()
        let image = try Renderer.render(project: project, content: content, media: [backdrop.reference.id: backdrop])
        let peak = MemoryProbe.peakFootprint()
        #expect((image.width, image.height) == (8128, 8128))
        let growth = Double(peak - min(before, peak)) / 1_073_741_824
        print("perf.render8k_image_backdrop.peak_growth_gb=\(growth)")
        #expect(growth <= 2, "peak growth \(growth) GB")
    }

    @Test("[S3-AC12] [S3-AC19] a 4K gradient backdrop renders in ≤ 500 ms (median of 10, release)")
    func fourKGradient() throws {
        let project = Project(backdrop: .gradient(SunshotDefaults.gradient))
        let content = try SampleContent.image(width: 3712, height: 2032)
        _ = try Renderer.render(project: project, content: content)
        let clock = ContinuousClock()
        let samples = try (0..<10).map { _ in
            try clock.measure { _ = try Renderer.render(project: project, content: content) }
        }
        let median = samples.sorted()[5]
        print("perf.render4k_gradient.median=\(median)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }
}
