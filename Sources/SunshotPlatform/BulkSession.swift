public import AppKit
public import Foundation
public import Observation
public import SunshotCore
public import SunshotRender

/// S14 batch state: the items sharing the editor's one style, their strip thumbnails, the selection shown on the
/// canvas, and the batch export. Decoding, thumbnails and export run off the main actor.
@MainActor
@Observable
public final class BulkSession {
    public let editor: EditorModel
    public private(set) var batch = BulkBatch()
    public private(set) var thumbnails: [UUID: CGImage] = [:]
    /// Items that couldn't be read, with the reason (shown as an error badge, never an alert).
    public private(set) var itemErrors: [UUID: String] = [:]
    public internal(set) var exportState: BulkExportState = .idle
    /// The export file-name template: the editor's, which follows Settings ▸ Filename format (S7).
    public var exportTemplate: String { editor.filenameTemplate }
    @ObservationIgnored private var proxies: [UUID: BulkProxy] = [:]
    @ObservationIgnored private var thumbnailGeneration = 0
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored var exportTask: Task<BulkReport, Never>?

    public init(editor: EditorModel) {
        self.editor = editor
        editor.bulkDropHandler = { [weak self] urls in await self?.importURLs(urls) ?? false }
    }

    public var isActive: Bool { !batch.isEmpty }
    public var items: [BulkItem] { batch.items }
    public var selectedID: UUID? { batch.selectedID }

    // MARK: Import

    /// Adds files and folders to the batch. Returns false (drop refused) when nothing usable was offered.
    @discardableResult
    public func importURLs(_ urls: [URL]) async -> Bool {
        let collected = await Task.detached(priority: .userInitiated) { Self.collect(urls) }.value
        let previousSelection = batch.selectedID
        let result = batch.add(collected.items)
        editor.notice = UIStrings.batchAddNotice(result, skipped: collected.skipped)
        guard result.added > 0 else { return result.duplicates > 0 }
        if batch.selectedID != previousSelection { await showSelected() }
        await refreshThumbnails()
        return true
    }

    nonisolated static func collect(_ urls: [URL]) -> BulkImportCollector.Result {
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        return BulkImportCollector.collect(urls, isSupported: isSupportedImageFile)
    }

    // MARK: Selection and order

    public func select(_ id: UUID) async {
        guard batch.selectedID != id, batch.select(id) else { return }
        await showSelected()
    }

    /// ← (-1) / → (+1) in the strip.
    public func selectAdjacent(_ offset: Int) async {
        guard batch.selectAdjacent(offset) else { return }
        await showSelected()
    }

    /// Removes an item; the next one is shown. Removing the last item closes the batch and empties the canvas.
    public func remove(_ id: UUID) async {
        let wasSelected = batch.selectedID == id
        batch.remove(id)
        forget(id)
        if batch.isEmpty {
            close()
            await editor.perform { $0.showBulkContent(nil) }.value
        } else if wasSelected {
            await showSelected()
        }
    }

    public func removeSelected() async {
        guard let id = batch.selectedID else { return }
        await remove(id)
    }

    /// Move Left (-1) / Move Right (+1).
    public func nudge(_ id: UUID, by offset: Int) { batch.nudge(id, by: offset) }

    /// Drag a thumbnail onto another.
    public func move(_ id: UUID, onto target: UUID) { batch.move(id, onto: target) }

    /// Empties the batch; the image currently on the canvas stays as a single image.
    public func close() {
        exportTask?.cancel()
        batch.removeAll()
        thumbnails = [:]
        itemErrors = [:]
        proxies = [:]
        thumbnailGeneration += 1
        selectionGeneration += 1
        exportState = .idle
    }

    private func forget(_ id: UUID) {
        thumbnails[id] = nil
        itemErrors[id] = nil
        proxies[id] = nil
    }

    /// Decodes the selected item at full size (off-main) and shows it on the canvas without an undo step.
    func showSelected() async {
        selectionGeneration += 1
        let generation = selectionGeneration
        guard let item = batch.selectedItem else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try BulkExporter.loadFullImage(item) }
        }.value
        guard generation == selectionGeneration else { return }
        switch result {
        case .success(let image):
            itemErrors[item.id] = nil
            await editor.perform { $0.showBulkContent(image) }.value
        case .failure(let error):
            let reason = Self.describe(error)
            itemErrors[item.id] = reason
            editor.notice = UIStrings.cantOpenBatchItem(item.displayName, reason: reason)
            await editor.perform { $0.showBulkContent(nil) }.value
        }
    }

    // MARK: Thumbnails

    /// Renders every strip thumbnail with the current style, one at a time, off-main. Proxies are decoded
    /// (downsampled) once per item and cached; a newer refresh supersedes an older one.
    public func refreshThumbnails() async {
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        let project = editor.project
        let media = editor.session.document.media
        for item in batch.items {
            guard generation == thumbnailGeneration, !Task.isCancelled else { return }
            let cached = proxies[item.id]
            if cached == nil, itemErrors[item.id] != nil { continue }
            let result = await Task.detached(priority: .utility) {
                Result { () throws -> (BulkProxy, CGImage) in
                    let proxy = try cached ?? Self.loadProxy(item)
                    return (proxy, try BulkThumbnailer.render(proxy, project: project, media: media))
                }
            }.value
            guard generation == thumbnailGeneration, batch.index(of: item.id) != nil else { continue }
            switch result {
            case .success(let (proxy, thumbnail)):
                proxies[item.id] = proxy
                thumbnails[item.id] = thumbnail
            case .failure(let error):
                itemErrors[item.id] = Self.describe(error)
            }
        }
    }

    /// The proxy cached for `id` (tests check its size).
    public func proxy(for id: UUID) -> BulkProxy? { proxies[id] }

    nonisolated static func loadProxy(_ item: BulkItem) throws -> BulkProxy {
        let accessing = item.accessURL.startAccessingSecurityScopedResource()
        defer { if accessing { item.accessURL.stopAccessingSecurityScopedResource() } }
        return try BulkThumbnailer.proxy(for: item.url)
    }

    /// One-line reason for a failed item.
    nonisolated static func describe(_ error: any Error) -> String {
        switch error {
        case ExportError.tooLarge: UIStrings.exportTooLarge
        case ExportError.formatUnavailable(let format): UIStrings.formatUnavailable(format)
        case FileExportError.writeFailed(let reason): reason
        default: BulkExporter.describe(error)
        }
    }
}
