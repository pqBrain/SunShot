import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Bulk export")
struct BulkExporterTests {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    /// 2026-11-17 08:19:05 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_903_545)

    private func job(_ items: [BulkItem], folder: BulkFolder, project: Project = Project()) -> BulkExportJob {
        BulkExportJob(items: items, project: project, folder: folder.url, date: now)
    }

    @Test("[S14-AC12] every item is written with the shared style and options, identical to a single export")
    func exportsAll() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let items = [
            try source.png("a.png", width: 120, height: 80),
            try source.png("b.png", width: 60, height: 90, red: 0.7),
            try source.png("c.png", width: 200, height: 40, red: 0.9),
        ]
        var style = EditorSession()
        style.setCornerRadius(18)
        style.setExportFormat(.jpeg)
        style.setExportScale(.x2)
        let report = await BulkExporter.run(job(items, folder: output, project: style.project), timeZone: utc)

        #expect(report.isCompleteSuccess)
        #expect(
            try output.contents() == (1...3).map { "screenshot_2x_sunshot_2026-11-17_08-19-05_\($0).jpg" })
        for (item, url) in zip(items, report.written) {
            let single = EditorSession(
                document: EditorDocument(
                    project: style.project, content: ContentImage(try BulkExporter.loadFullImage(item))))
            #expect(try Data(contentsOf: url) == single.exportImageData(), "\(item.displayName)")
        }
    }

    @Test("[S14-AC13] names that exist in the folder get a suffix; nothing is overwritten")
    func neverOverwrites() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let items = [try source.png("home.png"), try source.png("login.png")]
        try Data("keep".utf8).write(to: output.file("home_1.png"))
        var exportJob = job(items, folder: output)
        exportJob.template = "{NAME}"
        let report = await BulkExporter.run(exportJob, timeZone: utc)
        #expect(try output.contents() == ["home_1-2.png", "home_1.png", "login_2.png"])
        #expect(try Data(contentsOf: output.file("home_1.png")) == Data("keep".utf8))
        #expect(report.written.map(\.lastPathComponent) == ["home_1-2.png", "login_2.png"])
    }

    @Test("[S14-AC14] progress names each item before it and counts it after it, ending at 1.0")
    func progress() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let items = try (0..<4).map { try source.png("\($0).png", width: 20, height: 20) }
        var events: [BulkProgress] = []
        _ = await BulkExporter.run(job(items, folder: output), progress: { events.append($0) })
        #expect(events.count == 8)
        #expect(events.map(\.completed) == [0, 1, 1, 2, 2, 3, 3, 4])
        #expect(events.map(\.currentName) == ["0.png", nil, "1.png", nil, "2.png", nil, "3.png", nil])
        #expect(events.last?.fractionCompleted == 1)
    }

    @Test("[S14-AC15] cancelling stops before the next item and keeps the files already written")
    func cancel() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let items = try (0..<10).map { try source.png("\($0).png", width: 20, height: 20) }
        let exportJob = job(items, folder: output)
        let task = Task.detached {
            await BulkExporter.run(
                exportJob,
                progress: { progress in
                    if progress.completed == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                })
        }
        let report = await task.value
        #expect(report.wasCancelled)
        #expect(report.written.count == 3)
        #expect(report.notProcessed == 7)
        #expect(try output.contents().count == 3, "no partial or temporary file is left behind")
    }

    @Test("[S14-AC16] corrupt, missing and too-large items are reported and the others still export")
    func perItemErrors() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let corrupt = source.file("corrupt.png")
        try Data("nope".utf8).write(to: corrupt)
        let items = [
            try source.png("a.png"), try source.png("b.png"), BulkItem(url: corrupt),
            BulkItem(url: source.file("gone.png")), try source.png("e.png"),
        ]
        let report = await BulkExporter.run(job(items, folder: output))
        #expect(report.written.count == 3)
        #expect(report.failures.map(\.name) == ["corrupt.png", "gone.png"])
        #expect(report.failures.map(\.reason) == [ImageLoadError.unreadable.reason, "The file no longer exists."])
        #expect(try output.contents().count == 3)

        let huge = try Fixtures.solid(width: 9000, height: 20)
        let tooLarge = await BulkExporter.run(
            job([items[0]], folder: output), loader: { _ in huge }, describe: { "\($0)" })
        #expect(tooLarge.failures.first?.reason.hasPrefix("tooLarge") == true)
        #expect(BulkExporter.describe(ExportError.formatUnavailable(.webp)).isEmpty == false)
    }

    @Test("[S14-AC17] items are loaded strictly one after another, in batch order")
    func sequential() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let items = try (0..<5).map { try source.png("\($0).png", width: 20, height: 20) }
        var loaded: [String] = []
        var inFlight = 0
        var maxInFlight = 0
        let report = await BulkExporter.run(
            job(items, folder: output),
            loader: { item in
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                defer { inFlight -= 1 }
                loaded.append(item.displayName)
                return try BulkExporter.loadFullImage(item)
            })
        #expect(report.written.count == 5)
        #expect(maxInFlight == 1)
        #expect(loaded == items.map(\.displayName))
    }
}

/// Batch export memory budget, in the release perf stage. CoreGraphics keeps a small, count-limited cache of
/// recent render buffers for ImageIO-decoded content (see DECISIONS S14), so the footprint climbs for the first
/// ~16 items and then stays flat; the budget checks that it is flat (bounded), not that it is zero.
extension RenderPerformanceTests {
    @Test("[S14-AC17] a 40-image export of 3000×2000 at 2× plateaus: the last 20 items add ≤ 64 MB, peak ≤ 1.5 GB")
    func bulkExportMemory() async throws {
        let source = try BulkFolder()
        let output = try BulkFolder()
        defer {
            source.cleanUp()
            output.cleanUp()
        }
        let count = 40
        let items = try (0..<count).map {
            try source.png("\($0).png", width: 3000, height: 2000, red: Double($0) / Double(count))
        }
        let before = MemoryProbe.footprint()
        var samples: [UInt64] = []
        let report = await BulkExporter.run(
            BulkExportJob(items: items, project: Project(), folder: output.url),
            loader: { item in
                // Sampled while the full-size image is alive, and again after each item below.
                let image = try BulkExporter.loadFullImage(item)
                samples.append(MemoryProbe.footprint())
                return image
            },
            progress: { _ in samples.append(MemoryProbe.footprint()) })
        func megabytes(_ value: UInt64) -> Int {
            Int(value.subtractingReportingOverflow(before).partialValue / 1_048_576)
        }
        // Three samples per item: before, while decoded, after.
        let firstHalf = megabytes(samples.prefix(samples.count / 2).max() ?? before)
        let overall = megabytes(samples.max() ?? before)
        print("perf.bulk.export_40x6mp_first20_mb=\(firstHalf) perf.bulk.export_40x6mp_all_mb=\(overall)")
        #expect(report.written.count == count)
        #expect(overall - firstHalf <= 64, "grew \(overall - firstHalf) MB over the last 20 items")
        #expect(overall <= 1536, "grew \(overall) MB")
    }
}
