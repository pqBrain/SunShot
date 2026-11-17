public import CoreGraphics
public import Foundation
public import SunshotCore

/// The imported image. Identity-compared so undo snapshots stay cheap (pixels are never copied).
public struct ContentImage: Equatable, Sendable {
    public let id: UUID
    public let image: CGImage
    /// The imported file's original bytes (saved unchanged in documents); nil for generated content.
    public let data: Data?

    public init(_ image: CGImage, id: UUID = UUID(), data: Data? = nil) {
        self.id = id
        self.image = image
        self.data = data
    }

    public var pixelSize: PixelSize { PixelSize(width: image.width, height: image.height) }

    public static func == (lhs: ContentImage, rhs: ContentImage) -> Bool { lhs.id == rhs.id }
}

/// Everything the user edits: style + content + media (user backdrop images, keyed by `MediaReference.id`).
/// The content is an image or a code snippet, never both.
public struct EditorDocument: Equatable, Sendable {
    public var project: Project
    public var content: ContentImage?
    public var media: [String: MediaAsset]
    /// The theme last applied ("No Theme" when nil); undo restores it with the style.
    public var theme: Theme?
    /// Code-snippet content (S11); when set it is the content and `content` is nil.
    public var snippet: CodeSnippet?
    /// Non-destructive crop of the content image (S10), in its pixels; nil shows the whole image.
    public var crop: CropRect?
    /// Video content (S13); it is the content while `content` is its first frame (see `activeVideo`).
    public var video: VideoContent?
    /// S15: images for the other screenshots, keyed by screenshot number (1, 2…). A slot without an image shows
    /// the main content. Kept when the arrangement changes, so switching back shows them again.
    public var slots: [Int: ContentImage]

    public init(
        project: Project = Project(), content: ContentImage? = nil, media: [String: MediaAsset] = [:],
        theme: Theme? = nil, snippet: CodeSnippet? = nil, crop: CropRect? = nil, video: VideoContent? = nil,
        slots: [Int: ContentImage] = [:]
    ) {
        self.slots = slots
        self.project = project
        self.content = content
        self.media = media
        self.theme = theme
        self.snippet = snippet
        self.crop = crop
        self.video = video
    }
}

/// The single document store: all edits go through here, so every change is undoable.
public struct EditorSession: Sendable {
    public static let importActionName = "Import Image"
    public static let replaceActionName = "Replace Image"
    public static let clearActionName = "Clear Content"

    public internal(set) var history: UndoStack<EditorDocument>

    public init(document: EditorDocument = EditorDocument()) {
        history = UndoStack(document)
    }

    public var document: EditorDocument { history.current }
    public var hasContent: Bool { document.content != nil || document.snippet != nil }

    /// Canvas size at 1×, or nil when empty.
    public var canvasSize: PixelSize? {
        guard let contentSize = document.contentPixelSize else { return nil }
        return CanvasLayout.compute(contentSize: contentSize, project: document.project).canvasSize
    }

    /// Sets (or replaces) the content image as one undoable step. With `autoBackdrop`, the first image of a
    /// document whose backdrop is still untouched also gets the first auto background of its colours (S7), in the
    /// same undo step.
    public mutating func setContent(_ image: CGImage, data: Data? = nil, autoBackdrop: Bool = false) {
        let first = !hasContent
        let name = first ? Self.importActionName : Self.replaceActionName
        history.apply(name) {
            $0.content = ContentImage(image, data: data)
            $0.snippet = nil
            $0.crop = nil
            if autoBackdrop && first && $0.project.hasUntouchedBackdrop {
                let palette = ContentPalette.extract(from: image)
                let shuffle = $0.project.backdropSettings.autoShuffle
                if let wallpaper = AutoBackground.suggestions(palette: palette, shuffle: shuffle).first {
                    Self.select(wallpaper, in: &$0)
                }
            }
        }
    }

    /// Decodes `data` and sets it as content. Throws without touching state if the data isn't a usable image.
    public mutating func importImage(data: Data) throws {
        setContent(try ImageLoader.load(data), data: data)
    }

    /// Removes the content (undoable). No-op when already empty.
    public mutating func clearContent() {
        guard hasContent else { return }
        history.apply(Self.clearActionName) {
            $0.content = nil
            $0.snippet = nil
            $0.crop = nil
            $0.slots = [:]
        }
    }

    public mutating func undo() { history.undo() }
    public mutating func redo() { history.redo() }

    /// Renders the current document, or nil when there's no content.
    public func render(scale: Double = 1) throws -> CGImage? {
        try Renderer.render(document: document, scale: scale)
    }

    /// PNG of the full canvas at `scale`. Throws `RenderError.noContent` when empty.
    public func exportPNG(scale: Double = 1) throws -> Data {
        guard let image = try render(scale: scale) else { throw RenderError.noContent }
        return try ImageCodec.pngData(image)
    }
}
