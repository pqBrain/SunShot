import AppKit
public import Foundation
public import SunshotCore
import SunshotRender

/// S14 batch export: every item with the shared style and S4 export options, to one folder.
extension BulkSession {
    public var isExporting: Bool { exportState.isRunning }
    public var canExportAll: Bool { isActive && !isExporting }

    public var progress: BulkProgress? {
        if case .running(let progress) = exportState { return progress }
        return nil
    }

    public var report: BulkReport? {
        if case .finished(let report) = exportState { return report }
        return nil
    }

    /// Exports all items to `folder`, off the main actor, one at a time. Returns nil when export isn't possible.
    @discardableResult
    public func exportAll(to folder: URL, date: Date = Date()) async -> BulkReport? {
        guard canExportAll else { return nil }
        let job = BulkExportJob(
            items: batch.items, project: editor.project, media: editor.session.document.media, folder: folder,
            template: exportTemplate, date: date)
        exportState = .running(BulkProgress(total: job.items.count))
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await BulkExporter.run(
                job, describe: BulkSession.describe, progress: { progress in await self?.update(progress) })
        }
        exportTask = task
        let report = await task.value
        exportTask = nil
        exportState = .finished(report)
        return report
    }

    /// Stops before the next item; files already written stay.
    public func cancelExport() { exportTask?.cancel() }

    /// Hides the summary.
    public func dismissReport() {
        if report != nil { exportState = .idle }
    }

    /// Selects the exported files in Finder.
    public func revealExported() {
        guard let written = report?.written, !written.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(written)
    }

    private func update(_ progress: BulkProgress) {
        if isExporting { exportState = .running(progress) }
    }
}

/// Drop routing between the single-image flow (S1) and a batch.
extension EditorModel {
    /// Several supported images, or any folder, go to the batch; a single image opens as before.
    public func isBatchDrop(_ urls: [URL]) -> Bool {
        urls.filter(isSupportedImageFile).count > 1 || BulkImportCollector.containsDirectory(urls)
    }

    /// Whether the canvas accepts this drop: a supported image, or a folder.
    public func canAcceptDrop(_ urls: [URL]) -> Bool {
        urls.contains(where: isSupportedImageFile) || BulkImportCollector.containsDirectory(urls)
    }
}
