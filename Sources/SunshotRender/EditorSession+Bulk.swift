public import CoreGraphics
public import Foundation
public import SunshotCore

/// S14: the batch item shown on the canvas. Switching items is navigation, not an edit: the content is swapped in
/// every undo/redo state, so history only tracks the shared style and undo never changes which image is shown.
extension EditorSession {
    /// Shows `image` (nil = nothing) as the content without recording an undo step.
    public mutating func showBulkContent(_ image: CGImage?) {
        let content = image.map { ContentImage($0) }
        history.rewriteAll { $0.content = content }
    }

    /// The export of `image` with this session's style and media, through the same path as a single export.
    public func exportData(forBulkImage image: CGImage) throws -> (data: Data, plan: ExportPlan) {
        let item = EditorSession(
            document: EditorDocument(project: document.project, content: ContentImage(image), media: document.media))
        guard let plan = item.exportPlan else { throw RenderError.noContent }
        return (try item.exportImageData(), plan)
    }
}
