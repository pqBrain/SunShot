import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

/// Document budgets. Only enforced when `SUNSHOT_PERF=1` (the gate's perf stage runs suites matching
/// `RenderPerformanceTests` in release mode, serially).
@Suite("Document performance", .serialized, .enabled(if: ProcessInfo.processInfo.environment["SUNSHOT_PERF"] == "1"))
struct DocumentRenderPerformanceTests {
    @Test("[S7-AC20] after save + reload: 1×, 2× and 4K exports are byte-identical; 4K renders in ≤ 500 ms median")
    func reloadParityAndBudget() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 3712, height: 2032))
        try session.importBackdropImage(
            data: Fixtures.encode(try Fixtures.solid(width: 1600, height: 900), as: .png), fileName: "b.png")
        session.setCornerStyle(.round)
        session.setShadowStyle(.spread)
        session.setShadowIntensity(.high)
        let url = folder.file("big.sunshot")
        try DocumentPackage.write(session.document, to: url)
        var reloaded = EditorSession(document: try DocumentPackage.read(from: url).document)
        #expect(reloaded.document == session.document)
        for scale in [ExportScale.x1, .x2, .k4] {
            session.setExportScale(scale)
            reloaded.setExportScale(scale)
            #expect(try session.exportImageData() == reloaded.exportImageData(), "scale \(scale.rawValue)")
        }
        let plan = try #require(reloaded.exportPlan)
        _ = try reloaded.render(scale: plan.renderScale)
        let clock = ContinuousClock()
        let samples = (0..<10).map { _ in clock.measure { _ = try? reloaded.render(scale: plan.renderScale) } }
        let median = samples.sorted()[5]
        print("perf.document_reload_render4k.median=\(median)")
        #expect(median <= .milliseconds(500), "median \(median)")
    }

    @Test("[S7-AC21] 8000² content + 8000² backdrop: save and load ≤ 3 s each, ≤ 1.5 GB growth, media stored once")
    func largeDocument() throws {
        let folder = try ScratchFolder()
        defer { folder.cleanUp() }
        let contentData = try Fixtures.encode(try Fixtures.solid(width: 8000, height: 8000, red: 0.1), as: .png)
        let backdropData = try Fixtures.encode(try Fixtures.solid(width: 8000, height: 8000, red: 0.7), as: .png)
        var session = EditorSession()
        try session.importImage(data: contentData)
        try session.importBackdropImage(data: backdropData, fileName: "huge.png")
        let document = session.document
        let url = folder.file("huge.sunshot")
        let before = MemoryProbe.footprint()
        let clock = ContinuousClock()
        let save = try clock.measure { try DocumentPackage.write(document, to: url) }
        var loaded: LoadedDocument?
        let load = try clock.measure { loaded = try DocumentPackage.read(from: url) }
        let growth = Double(MemoryProbe.peakFootprint() - min(before, MemoryProbe.peakFootprint())) / 1_073_741_824
        print("perf.document_8k.save=\(save) load=\(load) peak_growth_gb=\(growth)")
        #expect(save <= .seconds(3), "save \(save)")
        #expect(load <= .seconds(3), "load \(load)")
        #expect(growth <= 1.5, "peak growth \(growth) GB")
        #expect(loaded?.document == document)

        let mediaBytes = contentData.count + backdropData.count
        let json = try Data(contentsOf: url.appendingPathComponent("document.json"))
        #expect(json.count < 64 * 1024, "media must not be embedded in the JSON")
        let packageBytes = try FileManager.default.subpathsOfDirectory(atPath: url.path).reduce(0) { total, path in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(path).path)
            return total
                + ((attributes[.type] as? FileAttributeType) == .typeRegular ? (attributes[.size] as? Int ?? 0) : 0)
        }
        #expect(Double(packageBytes) <= 1.1 * Double(mediaBytes), "package \(packageBytes) vs media \(mediaBytes)")
    }
}
