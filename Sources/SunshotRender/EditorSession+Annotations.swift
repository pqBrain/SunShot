public import Foundation
public import SunshotCore

/// Annotation edits (S9). Each is one named undo step; drags go through `beginGesture` / `setAnnotations` /
/// `endGesture` so a whole drag is one step. Edits that change nothing record nothing.
extension EditorSession {
    public var annotations: AnnotationLayer { project.annotations }

    /// Long edge of the content in pixels (1000 when empty): sizes S/M/L and offsets scale with it.
    public var contentLongEdge: Double {
        guard let size = document.imageContentSize else { return 1000 }
        return Double(max(size.width, size.height))
    }

    /// Replaces the whole layer (used live during a drag, recorded as `actionName` outside a gesture).
    public mutating func setAnnotations(_ layer: AnnotationLayer, actionName: String) {
        editProject(actionName) { $0.annotations = layer }
    }

    public mutating func addAnnotation(_ annotation: Annotation) {
        editProject(AnnotationAction.add(annotation.kind)) { $0.annotations.add(annotation) }
    }

    public mutating func deleteAnnotations(_ ids: Set<UUID>) {
        editProject(AnnotationAction.delete) { $0.annotations.remove(ids) }
    }

    /// Copies `ids`, offset down-right; returns the copies' ids (empty when nothing was selected).
    @discardableResult
    public mutating func duplicateAnnotations(_ ids: Set<UUID>) -> Set<UUID> {
        let step = AnnotationDefaults.duplicateOffset * max(1, contentLongEdge / 1000)
        var copies = Set<UUID>()
        editProject(AnnotationAction.duplicate) {
            copies = $0.annotations.duplicate(ids, offset: AnnotationPoint(x: step, y: step))
        }
        return copies
    }

    public mutating func clearAnnotations() {
        editProject(AnnotationAction.clear) { $0.annotations.items.removeAll() }
    }

    /// Commits typed text: a new text annotation at `point`, or new text for the annotation `id`.
    /// Empty text adds nothing (and deletes an existing text annotation).
    @discardableResult
    public mutating func commitText(
        _ text: String, at point: AnnotationPoint, id: UUID?, style: AnnotationStyle
    ) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, let existing = annotations.annotation(id) {
            if trimmed.isEmpty {
                deleteAnnotations([id])
                return nil
            }
            editProject(AnnotationAction.editText) { $0.annotations.replace(existing.withText(text)) }
            return id
        }
        guard !trimmed.isEmpty else { return nil }
        let annotation = Annotation.make(
            .text, from: point, to: point, style: style, longEdge: contentLongEdge, text: text)
        addAnnotation(annotation)
        return annotation.id
    }

    /// Applies a style change (colour, size, line style…) to the annotations in `ids` as one step.
    public mutating func restyleAnnotations(_ ids: Set<UUID>, _ change: (inout Annotation) -> Void) {
        guard !ids.isEmpty else { return }
        editProject(AnnotationAction.style) { $0.annotations.update(ids, change) }
    }

    public mutating func setStepFormat(_ format: StepFormat) {
        editProject(AnnotationAction.stepFormat) { $0.annotations.stepFormat = format }
    }
}
