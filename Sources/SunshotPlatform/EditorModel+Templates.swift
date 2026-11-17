import CoreGraphics
public import SunshotCore
import SunshotRender

/// S12: the template gallery — live previews of every template with the current content (or sample content when
/// the document is empty), and applying a template as one undo step.
extension EditorModel {
    /// Opens the gallery and starts rendering its previews.
    public func showTemplateGallery() {
        templates.isPresented = true
        scheduleTemplateThumbnails()
    }

    /// Applies `template` to the open document (content kept) and closes the gallery.
    @discardableResult
    public func applyTemplate(_ template: DocumentTemplate) -> Task<Void, Never> {
        templates.isPresented = false
        return perform { $0.applyTemplate(template) }
    }

    /// Whether the document's style is exactly `template`'s (the gallery marks it).
    public func isCurrentTemplate(_ template: DocumentTemplate) -> Bool {
        EditorSession.project(template, keeping: project) == project
    }

    /// Renders the gallery previews off the main actor; skipped when they already show the current content.
    @discardableResult
    public func scheduleTemplateThumbnails() -> Task<Void, Never>? {
        let document = session.document
        let key = TemplatePreviewKey(
            content: document.content?.id, snippet: document.snippet, annotations: document.project.annotationLayer,
            title: document.project.frame.title, media: document.media.keys.sorted())
        guard key != templates.thumbnailKey || templates.thumbnails.isEmpty else { return nil }
        templates.thumbnailTask?.cancel()
        templates.thumbnailKey = key
        let list = templates.templates
        let task = Task { [weak self] in
            let images = await Task.detached(priority: .utility) {
                var images: [String: CGImage] = [:]
                for template in list {
                    if Task.isCancelled { break }
                    if let image = try? TemplateThumbnails.render(template, document: document) {
                        images[template.id] = image
                    }
                }
                return images
            }.value
            guard !Task.isCancelled, let self, self.templates.thumbnailKey == key else { return }
            self.templates.thumbnails = images
        }
        templates.thumbnailTask = task
        return task
    }
}
