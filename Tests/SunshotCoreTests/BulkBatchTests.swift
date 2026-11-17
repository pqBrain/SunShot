import Foundation
import Testing

@testable import SunshotCore

@Suite("Bulk batch: items, selection, order")
struct BulkBatchTests {
    private func item(_ name: String) -> BulkItem { BulkItem(url: URL(fileURLWithPath: "/tmp/batch/\(name)")) }

    private func names(_ batch: BulkBatch) -> [String] { batch.items.map(\.displayName) }

    @Test("[S14-AC1] added items keep their order and the first new item is selected")
    func addSelectsFirst() {
        var batch = BulkBatch()
        let result = batch.add([item("a.png"), item("b.jpg"), item("c.heic")])
        #expect(result == BulkAddResult(added: 3))
        #expect(names(batch) == ["a.png", "b.jpg", "c.heic"])
        #expect(batch.selectedItem?.displayName == "a.png")
        batch.add([item("d.png")])
        #expect(batch.selectedItem?.displayName == "a.png", "adding more keeps the selection")
    }

    @Test("[S14-AC4] duplicates (same standardized path) are ignored")
    func duplicates() {
        var batch = BulkBatch(items: [item("a.png")])
        let again = BulkItem(url: URL(fileURLWithPath: "/tmp/batch/./sub/../a.png"))
        let result = batch.add([again, item("b.png"), item("b.png")])
        #expect(result == BulkAddResult(added: 1, duplicates: 2))
        #expect(result.notAdded == 2)
        #expect(names(batch) == ["a.png", "b.png"])
    }

    @Test("[S14-AC4] a batch holds at most 500 items")
    func limit() {
        var batch = BulkBatch()
        let result = batch.add((0..<510).map { item("\($0).png") })
        #expect(batch.count == BulkBatch.maxItems)
        #expect(result == BulkAddResult(added: 500, overLimit: 10))
        let r1 = batch.add([item("late.png")]).overLimit
        #expect(r1 == 1)
    }

    @Test("[S14-AC9] selection moves with ← / → and stops at the ends; unknown ids are refused")
    func selection() {
        var batch = BulkBatch(items: [item("a"), item("b"), item("c")])
        let r2 = batch.selectAdjacent(-1)
        #expect(r2 == false)
        let r3 = batch.selectAdjacent(1)
        #expect(r3)
        #expect(batch.selectedIndex == 1)
        let r4 = batch.selectAdjacent(5)
        #expect(r4)
        #expect(batch.selectedIndex == 2)
        let r5 = batch.selectAdjacent(1)
        #expect(r5 == false)
        let r6 = batch.select(UUID())
        #expect(r6 == false)
        let r7 = batch.select(batch.items[0].id)
        #expect(r7)
        #expect(batch.selectedIndex == 0)
        var empty = BulkBatch()
        let r8 = empty.selectAdjacent(1)
        #expect(r8 == false)
        #expect(empty.selectedItem == nil)
    }

    @Test("[S14-AC10] removing the selected item selects the next, or the previous at the end")
    func remove() {
        var batch = BulkBatch(items: [item("a"), item("b"), item("c")])
        batch.select(batch.items[1].id)
        batch.remove(batch.items[1].id)
        #expect(names(batch) == ["a", "c"])
        #expect(batch.selectedItem?.displayName == "c")
        batch.remove(batch.items[1].id)
        #expect(batch.selectedItem?.displayName == "a")
        batch.remove(UUID())
        #expect(batch.count == 1)
        batch.add([item("z")])
        batch.remove(batch.items[1].id)
        #expect(batch.selectedItem?.displayName == "a", "removing an unselected item keeps the selection")
        batch.remove(batch.items[0].id)
        #expect(batch.isEmpty && batch.selectedID == nil)
        batch.add([item("q")])
        batch.removeAll()
        #expect(batch.isEmpty && batch.selectedID == nil)
    }

    @Test("[S14-AC11] moving reorders; the ends can't move further")
    func reorder() {
        var batch = BulkBatch(items: [item("a"), item("b"), item("c")])
        let a = batch.items[0].id
        let c = batch.items[2].id
        let r9 = batch.move(c, onto: a)
        #expect(r9)
        #expect(names(batch) == ["c", "a", "b"])
        let r10 = batch.nudge(c, by: -1)
        #expect(r10 == false)
        let r11 = batch.nudge(batch.items[2].id, by: 1)
        #expect(r11 == false)
        let r12 = batch.nudge(c, by: 1)
        #expect(r12)
        #expect(names(batch) == ["a", "c", "b"])
        let r13 = batch.move(c, to: 99)
        #expect(r13)
        #expect(names(batch) == ["a", "b", "c"])
        let r14 = batch.move(UUID(), to: 0)
        #expect(r14 == false)
        let r15 = batch.move(c, onto: UUID())
        #expect(r15 == false)
        let r16 = batch.nudge(UUID(), by: 1)
        #expect(r16 == false)
    }

    @Test("[S14-AC1] items know their display name, base name and security-scope URL")
    func itemNames() {
        let folder = URL(fileURLWithPath: "/tmp/batch", isDirectory: true)
        let item = BulkItem(url: folder.appendingPathComponent("My shot.final.png"), accessURL: folder)
        #expect(item.displayName == "My shot.final.png")
        #expect(item.baseName == "My shot.final")
        #expect(item.accessURL == folder)
        #expect(self.item("x.png").accessURL == self.item("x.png").url)
    }
}

@Suite("Bulk progress and report")
struct BulkProgressTests {
    @Test("[S14-AC14] fraction completed runs 0…1; an empty batch is complete")
    func fraction() {
        #expect(BulkProgress(total: 10, completed: 3).fractionCompleted == 0.3)
        #expect(BulkProgress(total: 0).fractionCompleted == 1)
        #expect(BulkExportState.running(BulkProgress(total: 1)).isRunning)
        #expect(!BulkExportState.idle.isRunning)
        #expect(!BulkExportState.finished(BulkReport(total: 0)).isRunning)
    }

    @Test("[S14-AC15] a cancelled report counts the items never reached")
    func notProcessed() {
        let failure = BulkFailure(id: UUID(), name: "x.png", reason: "bad")
        let report = BulkReport(
            total: 10, written: [URL(fileURLWithPath: "/tmp/1.png")], failures: [failure], wasCancelled: true)
        #expect(report.notProcessed == 8)
        #expect(!report.isCompleteSuccess)
        #expect(BulkReport(total: 1, written: [URL(fileURLWithPath: "/tmp/1.png")]).isCompleteSuccess)
    }
}
