import Foundation
import Testing

@testable import SunshotCore

@Suite("Bulk export file names")
struct BulkNamingTests {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    /// 2026-11-17 08:19:05 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_903_545)

    private func context(_ format: ExportFormat = .png) -> FilenameContext {
        FilenameContext(scale: .x2, date: now, width: 100, height: 80, format: format)
    }

    @Test("[S14-AC13] the default template gets a zero-padded index; one date for the run")
    func defaultTemplate() {
        let names = (0..<12).map {
            BulkNaming.fileName(
                template: SunshotDefaults.filenameTemplate, index: $0, count: 12, sourceName: "shot",
                context: context(), timeZone: utc)
        }
        #expect(names.first == "screenshot_2x_sunshot_2026-11-17_08-19-05_01.png")
        #expect(names.last == "screenshot_2x_sunshot_2026-11-17_08-19-05_12.png")
        #expect(Set(names).count == 12)
    }

    @Test("[S14-AC13] index padding follows the batch size")
    func padding() {
        #expect(BulkNaming.indexString(0, count: 9) == "1")
        #expect(BulkNaming.indexString(8, count: 10) == "09")
        #expect(BulkNaming.indexString(41, count: 500) == "042")
        #expect(BulkNaming.indexString(0, count: 0) == "1")
    }

    @Test("[S14-AC13] {INDEX} is used where written; {NAME} is the source name without braces")
    func tokens() {
        #expect(
            BulkNaming.itemTemplate("{INDEX}-{NAME}", index: 2, count: 3, sourceName: "Login {DATE}")
                == "3-Login DATE")
        #expect(
            BulkNaming.fileName(
                template: "{NAME}_{SCALE}", index: 0, count: 2, sourceName: "home", context: context(.jpeg),
                timeZone: utc) == "home_2x_1.jpg")
        #expect(
            BulkNaming.itemTemplate("   ", index: 0, count: 1, sourceName: "x")
                == SunshotDefaults.filenameTemplate + "_1")
    }

    @Test("[S14-AC13] clashes get -2, -3 before the extension; existing files are never reused")
    func allocator() {
        var allocator = BulkNameAllocator()
        let existing: Set<String> = ["a.png", "a-2.png"]
        let r17 = allocator.claim("a.png") { existing.contains($0) }
        #expect(r17 == "a-3.png")
        let r18 = allocator.claim("a.png") { existing.contains($0) }
        #expect(r18 == "a-4.png")
        let r20 = allocator.claim("b.png") { _ in false }
        #expect(r20 == "b.png")
        let r19 = allocator.claim("B.PNG") { _ in false }
        #expect(r19 == "B-2.PNG", "case-insensitive like APFS")
        let r21 = allocator.claim("noext") { _ in false }
        #expect(r21 == "noext")
        let r22 = allocator.claim("noext") { _ in false }
        #expect(r22 == "noext-2")
        let r23 = allocator.claim(".hidden") { _ in false }
        #expect(r23 == ".hidden")
        let r24 = allocator.claim(".hidden") { _ in false }
        #expect(r24 == ".hidden-2")
    }
}
