public import CoreGraphics
public import SunshotCore
import SunshotRender

/// Frame, colour-token and font actions for the inspector and the canvas title overlay.
extension EditorModel {
    /// Pixel size of the frame picker thumbnails (drawn at 2× for Retina).
    public static let frameThumbnailSize = PixelSize(width: 192, height: 128)

    /// Thumbnail of `kind` with this document's tokens, corners and UI scale, from the shared renderer.
    public func frameThumbnail(_ kind: FrameKind) -> CGImage? {
        FrameThumbnailCache.shared.thumbnail(kind, project: project, size: Self.frameThumbnailSize)
    }

    /// Typed HEX for a colour token. Returns false (nothing changes, no undo entry) when invalid.
    @discardableResult
    public func setTokenColor(_ token: ColorToken, hex: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setTokenColor(token, hex: hex) }
        return accepted
    }

    // MARK: Inline title editing

    public func beginTitleEdit() {
        finishContinuousEdit()
        session.beginTitleEdit()
    }

    /// Live update while typing (no undo entry until `commitTitleEdit`).
    public func updateTitle(_ text: String) { apply { $0.setFrameTitle(text) } }

    /// Return: one "Edit Frame Title" entry (none when unchanged).
    public func commitTitleEdit() {
        session.commitTitleEdit()
        Task { await refreshPreview() }
    }

    /// Esc: restores `original` without an undo entry.
    public func cancelTitleEdit(restoring original: String) {
        session.cancelTitleEdit(restoring: original)
        Task { await refreshPreview() }
    }

    /// Where the title bar sits on the canvas, as fractions (0…1) of the canvas size; nil without a title bar.
    public var titleBarUnitRect: CGRect? {
        guard let content = session.document.content, project.frame.kind.hasTitle else { return nil }
        let layout = CanvasLayout.compute(contentSize: content.pixelSize, project: project)
        let style = layout.styleScale
        let box = layout.frameRect
        let geometry = FrameGeometry(frame: project.frame, boxWidth: box.width / style, boxHeight: box.height / style)
        guard let bar = geometry.bar else { return nil }
        let width = Double(layout.canvasSize.width)
        let height = Double(layout.canvasSize.height)
        return CGRect(
            x: (box.x + bar.x * style) / width, y: (box.y + bar.y * style) / height, width: bar.width * style / width,
            height: bar.height * style / height)
    }

    /// VoiceOver value of the canvas preview: the frame title when the frame shows one.
    public var previewAccessibilityValue: String {
        project.frame.kind.hasTitle ? project.frame.displayTitle : ""
    }
}

/// Frame-picker thumbnails, re-rendered only when the inputs that affect them change.
@MainActor
final class FrameThumbnailCache {
    static let shared = FrameThumbnailCache()

    private struct Key: Hashable {
        let kind: FrameKind
        let border: Border
        let tokens: DesignTokens
        let uiScale: Double
    }

    private var images: [Key: CGImage] = [:]

    func thumbnail(_ kind: FrameKind, project: Project, size: PixelSize) -> CGImage? {
        let key = Key(kind: kind, border: project.border, tokens: project.tokens, uiScale: project.frame.uiScale)
        if let image = images[key] { return image }
        guard let image = try? Renderer.renderFrameThumbnail(kind, project: project, size: size) else { return nil }
        if images.count > 64 { images.removeAll() }
        images[key] = image
        return image
    }
}
