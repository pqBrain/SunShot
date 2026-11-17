public import AppKit
public import Foundation
public import Observation
import SunshotCore
public import SunshotRender

public struct AlertContent: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public static func == (lhs: AlertContent, rhs: AlertContent) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// Observable editor state for the UI. All edits go through `session` (the single, undoable document store);
/// decoding and rendering run off the main actor.
@MainActor
@Observable
public final class EditorModel {
    public static let openFailedTitle = "Can't open this file"
    public static let exportFailedTitle = "Couldn't export the image"
    public static let multipleFilesNotice = "Only one image is supported for now"
    /// Imports slower than this show a progress indicator.
    public static let defaultProgressDelay: Duration = .milliseconds(250)

    public private(set) var session = EditorSession()
    public private(set) var preview: CGImage?
    public private(set) var isImporting = false
    public private(set) var showsProgress = false
    public var alert: AlertContent?
    public var notice: String?
    private var renderGeneration = 0
    private let progressDelay: Duration

    public init(progressDelay: Duration = EditorModel.defaultProgressDelay) {
        self.progressDelay = progressDelay
    }

    // MARK: State for the UI

    public var hasContent: Bool { session.hasContent }
    public var canUndo: Bool { session.history.canUndo && !isImporting }
    public var canRedo: Bool { session.history.canRedo && !isImporting }
    public var undoTitle: String { session.history.undoActionName.map { "Undo \($0)" } ?? "Undo" }
    public var redoTitle: String { session.history.redoActionName.map { "Redo \($0)" } ?? "Redo" }

    public var previewAccessibilityLabel: String {
        guard let size = session.canvasSize else { return "Preview, empty" }
        return "Preview, \(size.width) by \(size.height) pixels"
    }

    // MARK: Import

    /// Decodes off-main; on failure shows an alert and leaves the document untouched.
    public func importData(_ data: Data, fileName: String? = nil) async {
        isImporting = true
        let delay = progressDelay
        let progressTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { self?.showsProgress = true }
        }
        defer {
            progressTask.cancel()
            isImporting = false
            showsProgress = false
        }
        do {
            let image = try await Task.detached(priority: .userInitiated) { try ImageLoader.load(data) }.value
            session.setContent(image)
            await refreshPreview()
        } catch {
            let reason = (error as? ImageLoadError)?.reason ?? error.localizedDescription
            alert = AlertContent(
                title: Self.openFailedTitle, message: [fileName, reason].compactMap(\.self).joined(separator: ": "))
        }
    }

    public func importFile(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            await importData(try Data(contentsOf: url), fileName: url.lastPathComponent)
        } catch {
            alert = AlertContent(
                title: Self.openFailedTitle, message: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Drop handler: imports the first supported file. Returns false (drop refused) when none is supported.
    @discardableResult
    public func importDroppedFiles(_ urls: [URL]) async -> Bool {
        guard let first = urls.first(where: isSupportedImageFile) else { return false }
        if urls.count > 1 { notice = Self.multipleFilesNotice }
        await importFile(at: first)
        return true
    }

    public func canPaste(from pasteboard: NSPasteboard) -> Bool { PasteboardIO.hasImage(pasteboard) }

    public func paste(from pasteboard: NSPasteboard) async {
        guard let data = PasteboardIO.imageData(from: pasteboard) else { return }
        await importData(data, fileName: nil)
    }

    // MARK: Edit

    public func clearContent() async {
        session.clearContent()
        await refreshPreview()
    }

    public func undo() async {
        guard canUndo else { return }
        session.undo()
        await refreshPreview()
    }

    public func redo() async {
        guard canRedo else { return }
        session.redo()
        await refreshPreview()
    }

    // MARK: Export

    public func pngData() async throws -> Data {
        let session = self.session
        return try await Task.detached(priority: .userInitiated) { try session.exportPNG() }.value
    }

    /// Copies exactly one PNG representation of the full canvas.
    public func copyPNG(to pasteboard: NSPasteboard) async {
        do {
            PasteboardIO.writePNG(try await pngData(), to: pasteboard)
        } catch {
            alert = AlertContent(title: Self.exportFailedTitle, message: error.localizedDescription)
        }
    }

    /// Writes the PNG atomically; on failure nothing is left at `url` and an alert is shown.
    public func exportPNG(to url: URL) async {
        do {
            try FileExport.write(try await pngData(), to: url)
        } catch FileExportError.writeFailed(let reason) {
            alert = AlertContent(title: Self.exportFailedTitle, message: reason)
        } catch {
            alert = AlertContent(title: Self.exportFailedTitle, message: error.localizedDescription)
        }
    }

    public func suggestedExportName(now: Date = Date()) -> String { ExportNaming.interimFileName(date: now) }

    // MARK: Preview

    /// Re-renders the preview through the same renderer as export. Stale renders are discarded.
    public func refreshPreview() async {
        renderGeneration += 1
        let generation = renderGeneration
        let document = session.document
        let image = try? await Task.detached(priority: .userInitiated) {
            try Renderer.render(document: document, scale: 1)
        }.value
        if generation == renderGeneration { preview = image ?? nil }
    }
}
