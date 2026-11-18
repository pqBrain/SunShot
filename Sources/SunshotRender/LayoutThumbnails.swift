public import CoreGraphics
public import Foundation
public import SunshotCore

/// Identifies everything a layout thumbnail depends on except the preset itself: the style (with the current
/// placement removed, since each thumbnail replaces it), the content and the backdrop media.
public struct LayoutThumbnailKey: Hashable, Sendable {
    public let project: Project
    /// The image content's id (nil for a code snippet).
    public let contentID: UUID?
    /// S17: a code snippet is content too, so editing the code refreshes the thumbnails.
    public let snippet: CodeSnippet?
    public let mediaIDs: [String]
    /// S15: slot images by index (their ids), so a new slot image refreshes the thumbnails.
    public let slotIDs: [Int: UUID]
    public let maxSide: Int

    public init?(document: EditorDocument, maxSide: Int) {
        guard document.content != nil || document.snippet != nil else { return nil }
        var project = document.project
        project.placement = ContentPlacement()
        self.project = project
        contentID = document.content?.id
        snippet = document.snippet
        mediaIDs = document.media.keys.sorted()
        slotIDs = document.slots.mapValues(\.id)
        self.maxSide = maxSide
    }
}

/// Live layout preset thumbnails: the current document with each preset's transform, rendered by the one
/// `Renderer.render` at thumbnail scale.
public enum LayoutThumbnails {
    /// Long side of a thumbnail in pixels.
    public static let defaultMaxSide = 200

    /// Render scale that fits the document's canvas into `maxSide`, or nil when there's no content.
    public static func scale(for document: EditorDocument, maxSide: Int) -> Double? {
        guard let size = document.contentPixelSize else { return nil }
        let canvas = CanvasLayout.compute(contentSize: size, project: document.project).canvasSize
        return Double(max(maxSide, 1)) / Double(max(canvas.width, canvas.height))
    }

    /// One thumbnail per preset id. Empty when the document has no content.
    public static func render(
        document: EditorDocument, presets: [LayoutPreset], maxSide: Int = defaultMaxSide
    ) throws -> [String: CGImage] {
        guard let scale = scale(for: document, maxSide: maxSide) else { return [:] }
        var thumbnails: [String: CGImage] = [:]
        for preset in presets {
            var variant = document
            variant.project.placement = ContentPlacement(transform: preset.transform, layoutPresetID: preset.id)
            if let image = try Renderer.render(document: variant, scale: scale) { thumbnails[preset.id] = image }
        }
        return thumbnails
    }
}
