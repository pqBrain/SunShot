import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Bulk session (model)")
struct BulkSessionTests {
    private func makeSession() -> (EditorModel, BulkSession) {
        let model = EditorModel()
        return (model, BulkSession(editor: model))
    }

    private func pngs(_ directory: TempDirectory, _ names: [String]) throws -> [URL] {
        try names.enumerated().map { index, name in
            let url = directory.file(name)
            try TestImages.png(width: 40 + index * 10, height: 30, red: CGFloat(index) / 4).write(to: url)
            return url
        }
    }

    @Test("[S14-AC2] several images go to the batch, one image opens alone, nothing usable is refused")
    func dropRouting() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let urls = try pngs(directory, ["a.png", "b.png"])
        let text = directory.file("readme.txt")
        try Data("x".utf8).write(to: text)
        let (model, bulk) = makeSession()

        #expect(await model.importDroppedFiles([text]) == false)
        #expect(model.canAcceptDrop([text]) == false)
        #expect(await model.importDroppedFiles([urls[0]]))
        #expect(!bulk.isActive)
        #expect(model.session.history.undoActionName == EditorSession.importActionName)

        #expect(await model.importDroppedFiles(urls + [text]))
        #expect(bulk.items.map(\.displayName) == ["a.png", "b.png"])
        #expect(model.notice == UIStrings.batchAddNotice(BulkAddResult(added: 2), skipped: 1))
        #expect(model.notice != EditorModel.multipleFilesNotice)
        #expect(model.canAcceptDrop([directory.url]))
        #expect(model.isBatchDrop([directory.url]))
    }

    @Test("[S14-AC1] importing files then a folder keeps the order, shows the first and renders thumbnails")
    func importMany() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let files = try pngs(directory, ["b.png", "a.png"])
        let folder = directory.file("more")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TestImages.png(width: 70, height: 20).write(to: folder.appendingPathComponent("c.png"))
        let (model, bulk) = makeSession()

        #expect(await bulk.importURLs(files + [folder]))
        #expect(bulk.items.map(\.displayName) == ["b.png", "a.png", "c.png"])
        #expect(bulk.selectedID == bulk.items.first?.id)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 40, height: 30))
        #expect(model.preview != nil)
        #expect(bulk.thumbnails.count == 3)
        #expect(model.session.history.undoCount == 0, "showing a batch item is not an edit")
    }

    @Test("[S14-AC3] a folder's non-images are skipped with a notice")
    func skippedNotice() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        _ = try pngs(directory, ["shot.png"])
        try Data("x".utf8).write(to: directory.file("notes.txt"))
        let (model, bulk) = makeSession()
        #expect(await model.importDroppedFiles([directory.url]))
        #expect(bulk.items.count == 1)
        #expect(model.notice == "Skipped 1 file that isn't a supported image")
        #expect(
            UIStrings.batchAddNotice(BulkAddResult(), skipped: 3) == "Skipped 3 files that aren't supported images")
    }

    @Test("[S14-AC4] adding the same files again changes nothing and says so")
    func duplicatesNotice() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let urls = try pngs(directory, ["a.png", "b.png"])
        let (model, bulk) = makeSession()
        await bulk.importURLs(urls)
        #expect(await bulk.importURLs([urls[0]]) == true)
        #expect(bulk.items.count == 2)
        #expect(model.notice == "1 image was already in the batch")
        #expect(
            UIStrings.batchAddNotice(BulkAddResult(duplicates: 2), skipped: 0) == "2 images were already in the batch")
        #expect(
            UIStrings.batchAddNotice(BulkAddResult(overLimit: 4), skipped: 0)
                == "A batch holds up to 500 images; 4 weren't added")
        #expect(UIStrings.batchAddNotice(BulkAddResult(added: 1), skipped: 0) == nil)
    }

    @Test("[S14-AC5] a style edit applies to every item: thumbnails re-render, one undo step")
    func sharedStyle() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let (model, bulk) = makeSession()
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png", "c.png"]))
        let before = bulk.thumbnails
        await model.perform { $0.setBackdropKind(.gradient) }.value
        await bulk.refreshThumbnails()
        #expect(model.session.history.undoCount == 1)
        for item in bulk.items {
            let old = try #require(before[item.id])
            let new = try #require(bulk.thumbnails[item.id])
            #expect(old.dataProvider?.data != new.dataProvider?.data, "\(item.displayName) re-rendered")
            #expect(bulk.proxy(for: item.id) != nil)
        }
    }

    @Test("[S14-AC8] an unreadable item gets an error badge, never an alert; the others are fine")
    func unreadableItem() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let urls = try pngs(directory, ["a.png"])
        let corrupt = directory.file("broken.png")
        try Data("nope".utf8).write(to: corrupt)
        let (model, bulk) = makeSession()
        await bulk.importURLs(urls + [corrupt])
        let broken = try #require(bulk.items.last)
        #expect(bulk.itemErrors[broken.id] == ImageLoadError.unreadable.reason)
        #expect(bulk.thumbnails[broken.id] == nil)
        #expect(bulk.thumbnails[bulk.items[0].id] != nil)

        await bulk.select(broken.id)
        #expect(model.alert == nil)
        #expect(!model.hasContent)
        #expect(model.notice == UIStrings.cantOpenBatchItem("broken.png", reason: ImageLoadError.unreadable.reason))
    }

    @Test("[S14-AC9] selecting an item shows it at full size with no undo entry")
    func selectShows() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let (model, bulk) = makeSession()
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png", "c.png"]))
        await model.perform { $0.setCornerRadius(9) }.value
        await bulk.select(bulk.items[1].id)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 50, height: 30))
        await bulk.selectAdjacent(1)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 60, height: 30))
        await bulk.selectAdjacent(1)
        #expect(bulk.selectedID == bulk.items[2].id)
        #expect(model.session.history.undoCount == 1)
        await model.undo()
        #expect(model.project.border.radius == SunshotDefaults.cornerRadius)
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 60, height: 30))
    }

    @Test("[S14-AC10] remove shows the next item; removing the last empties the canvas; Close keeps the image")
    func removeAndClose() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let (model, bulk) = makeSession()
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png", "c.png"]))
        await bulk.select(bulk.items[1].id)
        await bulk.removeSelected()
        #expect(bulk.items.map(\.displayName) == ["a.png", "c.png"])
        #expect(model.session.document.content?.pixelSize == PixelSize(width: 60, height: 30))
        await bulk.remove(bulk.items[0].id)
        await bulk.remove(bulk.items[0].id)
        #expect(!bulk.isActive)
        #expect(!model.hasContent)

        await bulk.importURLs(try pngs(directory, ["d.png", "e.png"]))
        bulk.close()
        #expect(!bulk.isActive && bulk.thumbnails.isEmpty)
        #expect(model.hasContent, "the image on the canvas stays")
        await bulk.removeSelected()
    }

    @Test("[S14-AC11] Move Left / Move Right and drag reorder the batch")
    func reorder() async throws {
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let (_, bulk) = makeSession()
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png", "c.png"]))
        let ids = bulk.items.map(\.id)
        bulk.nudge(ids[2], by: -1)
        #expect(bulk.items.map(\.displayName) == ["a.png", "c.png", "b.png"])
        bulk.move(ids[1], onto: ids[0])
        #expect(bulk.items.map(\.displayName) == ["b.png", "a.png", "c.png"])
    }

    @Test("[S14-AC12] Export All writes every item to the folder and finishes with a summary")
    func exportAll() async throws {
        let directory = try TempDirectory()
        let output = try TempDirectory()
        defer {
            directory.cleanUp()
            output.cleanUp()
        }
        let (model, bulk) = makeSession()
        #expect(await bulk.exportAll(to: output.url) == nil, "nothing to export")
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png"]))
        await model.perform { $0.setExportFormat(.jpeg) }.value
        #expect(bulk.canExportAll)
        let report = try #require(await bulk.exportAll(to: output.url))
        #expect(report.isCompleteSuccess)
        #expect(bulk.report == report)
        #expect(bulk.progress == nil && !bulk.isExporting)
        let files = try FileManager.default.contentsOfDirectory(atPath: output.url.path)
        #expect(files.count == 2 && files.allSatisfy { $0.hasSuffix(".jpg") })
        #expect(UIStrings.exportSummary(report) == "Exported 2 images")
        bulk.dismissReport()
        #expect(bulk.exportState == .idle)
        bulk.cancelExport()
    }

    @Test("[S14-AC14] progress text counts the item being exported")
    func progressText() {
        #expect(UIStrings.exportingProgress(BulkProgress(total: 12, completed: 2)) == "Exporting 3 of 12")
        #expect(UIStrings.exportingProgress(BulkProgress(total: 12, completed: 12)) == "Exporting 12 of 12")
        #expect(UIStrings.imageCount(1) == "1 image")
    }

    @Test("[S14-AC15] a cancelled export's summary")
    func cancelledSummary() {
        let written = (0..<3).map { URL(fileURLWithPath: "/tmp/\($0).png") }
        let report = BulkReport(total: 10, written: written, wasCancelled: true)
        #expect(UIStrings.exportSummary(report) == "Cancelled — exported 3 of 10")
    }

    @Test("[S14-AC16] failures are summarised with each file's reason; too large uses the export wording")
    func failureSummary() {
        let failures = [
            BulkFailure(id: UUID(), name: "c.png", reason: ImageLoadError.unreadable.reason),
            BulkFailure(id: UUID(), name: "d.png", reason: "The file no longer exists."),
        ]
        let written = (0..<3).map { URL(fileURLWithPath: "/tmp/\($0).png") }
        let report = BulkReport(total: 5, written: written, failures: failures)
        #expect(UIStrings.exportSummary(report) == "Exported 3 of 5 — 2 failed")
        #expect(UIStrings.failureLine(failures[0]) == "c.png: The file is damaged or isn't an image.")
        #expect(BulkSession.describe(ExportError.tooLarge(width: 20000, height: 10)) == UIStrings.exportTooLarge)
        #expect(BulkSession.describe(ExportError.formatUnavailable(.webp)) == UIStrings.formatUnavailable(.webp))
        #expect(BulkSession.describe(FileExportError.writeFailed(reason: "Disk full")) == "Disk full")
        #expect(BulkSession.describe(ImageLoadError.empty) == ImageLoadError.empty.reason)
    }

    @Test("[S14-AC19] thumbnail labels for VoiceOver")
    func labels() {
        #expect(
            UIStrings.batchItemLabel(name: "shot.png", index: 1, count: 12, isSelected: true, hasError: false)
                == "Image 2 of 12, shot.png, selected")
        #expect(
            UIStrings.batchItemLabel(name: "bad.png", index: 0, count: 2, isSelected: false, hasError: true)
                == "Image 1 of 2, bad.png, can't open")
    }

    @Test(
        "[S14-AC18] menus and strip: Import Multiple / Export All shortcuts; Export All off without a batch or mid-export"
    )
    func menusAndStrip() async throws {
        #expect(MenuCatalog.item(.importMultiple)?.shortcut?.description == "⇧⌘O")
        #expect(MenuCatalog.item(.exportAll)?.shortcut?.description == "⌥⇧⌘E")
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let (_, bulk) = makeSession()
        #expect(!bulk.isActive && !bulk.canExportAll, "no strip and no Export All without a batch")
        await bulk.importURLs(try pngs(directory, ["a.png", "b.png", "c.png"]))
        #expect(bulk.isActive && bulk.canExportAll && UIStrings.imageCount(bulk.items.count) == "3 images")
        bulk.exportState = .running(BulkProgress(total: 3, completed: 1))
        #expect(bulk.isExporting && !bulk.canExportAll, "progress replaces the strip; Export All is off")
        #expect(bulk.progress.map(UIStrings.exportingProgress) == "Exporting 2 of 3")
        bulk.exportState = .finished(BulkReport(total: 3, written: []))
        #expect(bulk.report != nil && bulk.canExportAll && UIStrings.showInFinder == "Show in Finder")
    }
}
