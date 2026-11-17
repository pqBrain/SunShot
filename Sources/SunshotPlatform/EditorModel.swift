public import AppKit
public import Foundation
public import Observation
public import SunshotCore
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

    public internal(set) var session = EditorSession()
    public private(set) var preview: CGImage?
    public private(set) var isImporting = false
    public private(set) var showsProgress = false
    public var alert: AlertContent?
    /// Whether the style inspector panel is visible.
    public var showsInspector = true
    public var notice: String?
    /// Dark appearance picks the dark checkerboard behind transparent backdrops (preview only).
    public private(set) var isDarkAppearance = false
    private var renderGeneration = 0
    private let progressDelay: Duration
    /// An open colour-panel edit: merged into one undo step once the colour stops changing.
    var pendingContinuousEdit: (name: String, task: Task<Void, Never>)?

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
        finishContinuousEdit()
        guard canUndo else { return }
        session.undo()
        await refreshPreview()
    }

    public func redo() async {
        finishContinuousEdit()
        guard canRedo else { return }
        session.redo()
        await refreshPreview()
    }

    // MARK: Style (border, shadow)

    public var project: Project { session.project }

    /// Inspector controls are only enabled (and only show values) when there is content.
    public var isInspectorEnabled: Bool { hasContent }

    /// Applies an edit synchronously (so controls stay in step) and re-renders the preview in the background.
    /// Await the returned task to wait for the new preview.
    @discardableResult
    public func perform(_ change: (inout EditorSession) -> Void) -> Task<Void, Never> {
        finishContinuousEdit()
        return apply(change)
    }

    /// Applies without closing an open colour-panel edit.
    @discardableResult
    func apply(_ change: (inout EditorSession) -> Void) -> Task<Void, Never> {
        change(&session)
        return Task { await refreshPreview() }
    }

    /// Starts a continuous change (slider or handle drag); `endGesture` records it as a single undo step.
    public func beginGesture() {
        finishContinuousEdit()
        session.beginGesture()
    }

    public func endGesture(_ actionName: String) { session.endGesture(actionName) }

    /// Typed corner radius. Returns false (value unchanged) for non-numeric text.
    @discardableResult
    public func setCornerRadius(text: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setCornerRadius(text: text) }
        return accepted
    }

    /// Moves the light handle by one keyboard step (`large` = ⇧).
    public func nudgeLight(dx: Double, dy: Double, large: Bool) {
        let step = large ? UnitOffset.largeKeyboardStep : UnitOffset.keyboardStep
        let position = project.shadow.lightPosition.nudged(dx: dx * step, dy: dy * step)
        perform { $0.setLightPosition(position) }
    }

    /// Called by the window when Light/Dark changes; re-renders so the checkerboard matches.
    @discardableResult
    public func setDarkAppearance(_ isDark: Bool) -> Task<Void, Never>? {
        guard isDark != isDarkAppearance else { return nil }
        isDarkAppearance = isDark
        return Task { await refreshPreview() }
    }

    // MARK: Preview

    /// 1, or less for canvases whose long edge exceeds `SunshotDefaults.previewMaxSide` (huge custom sizes).
    public var previewScale: Double {
        guard let size = session.canvasSize else { return 1 }
        return min(1, Double(SunshotDefaults.previewMaxSide) / Double(max(size.width, size.height)))
    }

    /// Re-renders the preview through the same renderer as export. Stale renders are discarded.
    public func refreshPreview() async {
        renderGeneration += 1
        let generation = renderGeneration
        let document = session.document
        let grid = SunshotPalette.transparencyGrid(dark: isDarkAppearance)
        let scale = previewScale
        let image = try? await Task.detached(priority: .userInitiated) {
            try Renderer.render(document: document, scale: scale, showsTransparencyGrid: true, grid: grid)
        }.value
        if generation == renderGeneration { preview = image ?? nil }
    }
}
