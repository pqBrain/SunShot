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
    public internal(set) var preview: CGImage?
    public private(set) var isImporting = false
    public private(set) var showsProgress = false
    public var alert: AlertContent?
    /// Whether the style inspector panel is visible.
    public var showsInspector = true
    /// S17-AC3: the toolbar's Annotate button hid the annotation bar. Not saved: the bar shows again at launch.
    public internal(set) var hidesAnnotationBar = false
    public var notice: String?
    /// S6: the inspector section the canvas last asked to bring into view (click on backdrop / screenshot).
    public internal(set) var inspectorFocus: InspectorFocusRequest?
    /// S6: device pixels available to the preview (set by the view); nil renders one canvas pixel per pixel.
    public internal(set) var previewDisplayPixels: (width: Double, height: Double)?
    /// Export file-name template (Settings ▸ Filename format; S7).
    public var filenameTemplate = SunshotDefaults.filenameTemplate
    /// S7: style an untouched backdrop from the first imported image (Settings; off unless a controller turns it on).
    public var autoBackdropOnImport = false
    /// Annotate mode state (S9).
    public let annotate = AnnotationEditor()
    /// S6: layout thumbnails, preset animation and position-drag guides.
    public let layout = LayoutState()
    /// S10: screen / website capture state and the crop dialog's draft.
    public let capture = CaptureController()
    public let crop = CropEditor()
    /// S12: template gallery state and previews.
    public let templates = TemplateGalleryState()
    /// S13: Animate mode, playback and video export.
    public let animate = AnimateState()
    /// Dark appearance picks the dark checkerboard behind transparent backdrops (preview only).
    public private(set) var isDarkAppearance = false
    var renderGeneration = 0
    /// `renderGeneration` of the latest `refreshPreview` request; a higher generation belongs to an animation.
    private var refreshGeneration = 0
    private var previewRequests = 0
    private var previewLoop: Task<Void, Never>?
    private let progressDelay: Duration
    /// An open colour-panel edit: merged into one undo step once the colour stops changing.
    var pendingContinuousEdit: (name: String, task: Task<Void, Never>)?
    /// S16: the side of the document not shown right now (Screenshot ⇄ Code), so switching back restores it.
    var stashedImage: ImageContentStash?
    var stashedSnippet: CodeSnippet?
    /// Set by the batch (S14): drops of several images or a folder go there instead of the single-image flow.
    public var bulkDropHandler: (@MainActor ([URL]) async -> Bool)?

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
            session.setContent(
                image, data: data, autoBackdrop: autoBackdropOnImport,
                plainFrame: ImageLoader.isSystemScreenshot(data))
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
            // Read off the main actor (a large or network-mounted file); importData decodes off it too.
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            await importData(data, fileName: url.lastPathComponent)
        } catch {
            alert = AlertContent(
                title: Self.openFailedTitle, message: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Drop handler: imports the first supported file. Returns false (drop refused) when none is supported.
    @discardableResult
    public func importDroppedFiles(_ urls: [URL]) async -> Bool {
        if let bulkDropHandler, isBatchDrop(urls) { return await bulkDropHandler(urls) }
        if !urls.contains(where: isSupportedImageFile), let video = urls.first(where: VideoLoader.isVideoFile) {
            await importVideo(at: video)
            return true
        }
        guard let first = urls.first(where: isSupportedImageFile) else { return false }
        if urls.count > 1 { notice = Self.multipleFilesNotice }
        await importFile(at: first)
        return true
    }

    public func canPaste(from pasteboard: NSPasteboard) -> Bool { PasteboardIO.hasImage(pasteboard) }

    /// S15: the first paste sets the content; later pastes add the next screenshot, trimmed (see `addScreenshot`).
    public func paste(from pasteboard: NSPasteboard) async {
        guard let data = PasteboardIO.imageData(from: pasteboard) else { return }
        do {
            let image = try await Task.detached(priority: .userInitiated) { try ImageLoader.load(data) }.value
            await addScreenshot(
                image, data: data, replacingName: EditorSession.importActionName,
                plainFrame: ImageLoader.isSystemScreenshot(data))
            await refreshPreview()
        } catch {
            alert = AlertContent(
                title: Self.openFailedTitle, message: (error as? ImageLoadError)?.reason ?? error.localizedDescription)
        }
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

    /// Whether the bottom of the canvas has a bar (Position / Crop, or the Animate timeline). S17-AC4: messages are
    /// stacked above it, never under it.
    public var showsBottomBar: Bool { hasContent && !annotate.isActive }

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

    /// 1 (or the display-fitted scale), or less for canvases whose long edge exceeds `SunshotDefaults.previewMaxSide` (huge custom sizes).
    /// S6: rendered at the displayed size when the preview area is larger than the canvas (see `PreviewSizing`).
    public var previewScale: Double {
        guard let size = session.canvasSize else { return 1 }
        return PreviewSizing.scale(canvas: size, displayPixels: previewDisplayPixels)
    }

    /// Re-renders the preview through the same renderer as export. Returns once the preview shows the latest
    /// document. Requests are coalesced: at most one render runs, and a burst of edits (a slider drag) queues
    /// a single follow-up render of the newest document instead of one render per edit.
    public func refreshPreview() async {
        scheduleLayoutThumbnails()
        renderGeneration += 1
        refreshGeneration = renderGeneration
        previewRequests += 1
        if let running = previewLoop { return await running.value }
        let loop = Task { await runPreviewLoop() }
        previewLoop = loop
        await loop.value
    }

    private func runPreviewLoop() async {
        var rendered = -1
        while rendered != previewRequests {
            rendered = previewRequests
            let image = await renderPreviewImage(session.document)
            // Shown even if newer edits are queued (it is newer than what is on screen), unless a preset
            // animation has taken over the preview since the latest request.
            if renderGeneration == refreshGeneration { preview = image }
        }
        previewLoop = nil
    }
}
