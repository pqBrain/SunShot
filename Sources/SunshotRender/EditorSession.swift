public import CoreGraphics
public import Foundation
public import SunshotCore

/// The imported image. Identity-compared so undo snapshots stay cheap (pixels are never copied).
public struct ContentImage: Equatable, Sendable {
    public let id: UUID
    public let image: CGImage

    public init(_ image: CGImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
    }

    public var pixelSize: PixelSize { PixelSize(width: image.width, height: image.height) }

    public static func == (lhs: ContentImage, rhs: ContentImage) -> Bool { lhs.id == rhs.id }
}

/// Everything the user edits: style + content.
public struct EditorDocument: Equatable, Sendable {
    public var project: Project
    public var content: ContentImage?

    public init(project: Project = Project(), content: ContentImage? = nil) {
        self.project = project
        self.content = content
    }
}

/// The single document store: all edits go through here, so every change is undoable.
public struct EditorSession: Sendable {
    public static let importActionName = "Import Image"
    public static let replaceActionName = "Replace Image"
    public static let clearActionName = "Clear Content"

    public private(set) var history: UndoStack<EditorDocument>

    public init(document: EditorDocument = EditorDocument()) {
        history = UndoStack(document)
    }

    public var document: EditorDocument { history.current }
    public var hasContent: Bool { document.content != nil }

    /// Canvas size at 1×, or nil when empty.
    public var canvasSize: PixelSize? {
        guard let content = document.content else { return nil }
        return CanvasLayout.compute(contentSize: content.pixelSize, project: document.project).canvasSize
    }

    /// Sets (or replaces) the content image as one undoable step.
    public mutating func setContent(_ image: CGImage) {
        let name = hasContent ? Self.replaceActionName : Self.importActionName
        history.apply(name) { $0.content = ContentImage(image) }
    }

    /// Decodes `data` and sets it as content. Throws without touching state if the data isn't a usable image.
    public mutating func importImage(data: Data) throws {
        setContent(try ImageLoader.load(data))
    }

    /// Removes the content (undoable). No-op when already empty.
    public mutating func clearContent() {
        guard hasContent else { return }
        history.apply(Self.clearActionName) { $0.content = nil }
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
