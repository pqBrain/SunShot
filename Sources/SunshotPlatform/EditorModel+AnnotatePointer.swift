public import Foundation
public import SunshotCore
import SunshotRender

/// Selection chrome for the overlay, in view points of the displayed canvas.
public struct SelectionOutline: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let centerX: Double
    public let centerY: Double
    public let width: Double
    public let height: Double
    /// Degrees, clockwise.
    public let rotation: Double
}

public struct HandleMark: Hashable, Sendable {
    public let handle: AnnotationHandle
    public let x: Double
    public let y: Double
}

/// Pointer input for Annotate mode. `viewWidth` × `viewHeight` is the size the whole canvas is displayed at.
extension EditorModel {
    /// Maps the displayed canvas to content pixels; nil without content.
    public func annotationMapping(viewWidth: Double, viewHeight: Double) -> ContentMapping? {
        guard let size = session.document.imageContentSize else { return nil }
        return ContentMapping(
            contentSize: size, project: project, viewWidth: viewWidth, viewHeight: viewHeight,
            origin: session.document.contentOrigin)
    }

    /// Pointer down. `additive` = ⌘ held; `clickCount` 2 on a text annotation opens it for editing.
    public func annotationPointerDown(
        x: Double, y: Double, viewWidth: Double, viewHeight: Double, additive: Bool = false, clickCount: Int = 1
    ) {
        guard annotate.isActive, let mapping = annotationMapping(viewWidth: viewWidth, viewHeight: viewHeight) else {
            return
        }
        commitTextEditing()
        endAnnotationDrag()
        let point = mapping.contentPoint(fromView: x, y)
        let tolerance = mapping.contentLength(fromView: AnnotationDefaults.hitTolerance)
        if clickCount >= 2, annotate.tool == .select,
            let hit = session.annotations.topmost(at: point, tolerance: tolerance), hit.kind == .text
        {
            annotate.selection = []
            annotate.textEditing = AnnotationEditor.TextEditing(
                point: AnnotationPoint(x: hit.bounds.x, y: hit.bounds.y), id: hit.id, text: hit.text)
            return
        }
        let context = AnnotationInteraction.Context(
            tool: annotate.tool, style: annotate.style, layer: session.annotations, selection: annotate.selection,
            longEdge: mapping.contentLongEdge, tolerance: tolerance,
            rotateOffset: mapping.contentLength(fromView: AnnotationDefaults.rotateHandleOffset))
        let result = AnnotationInteraction.press(at: point, additive: additive, in: context)
        annotate.selection = result.selection
        switch result.press {
        case .none:
            break
        case .drag(let drag):
            beginGesture()
            annotate.drag = drag
            apply { $0.setAnnotations(drag.layer, actionName: drag.actionName) }
        case .place(let annotation):
            perform { $0.addAnnotation(annotation) }
        case .editText(let at, let id):
            let existing = id.flatMap { session.annotations.annotation($0)?.text } ?? ""
            annotate.textEditing = AnnotationEditor.TextEditing(point: at, id: id, text: existing)
        }
    }

    /// Pointer moved while down. `snap` = ⇧ held (rotation snaps to 15°).
    public func annotationPointerDragged(x: Double, y: Double, viewWidth: Double, viewHeight: Double, snap: Bool) {
        guard var drag = annotate.drag,
            let mapping = annotationMapping(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return }
        drag.update(to: mapping.contentPoint(fromView: x, y), snap: snap)
        annotate.drag = drag
        apply { $0.setAnnotations(drag.layer, actionName: drag.actionName) }
    }

    /// Pointer up: the drag becomes one undo entry (none if nothing changed).
    public func annotationPointerUp() { endAnnotationDrag() }

    func endAnnotationDrag() {
        guard let drag = annotate.drag else { return }
        annotate.drag = nil
        endGesture(drag.actionName)
    }

    // MARK: Overlay geometry

    public func selectionOutlines(viewWidth: Double, viewHeight: Double) -> [SelectionOutline] {
        guard let mapping = annotationMapping(viewWidth: viewWidth, viewHeight: viewHeight) else { return [] }
        let ids = annotationSelection
        return session.annotations.items.filter { ids.contains($0.id) }.map { annotation in
            let box = annotation.bounds
            let center = mapping.viewPoint(fromContent: annotation.center)
            return SelectionOutline(
                id: annotation.id, centerX: center.x, centerY: center.y,
                width: mapping.viewLength(fromContent: box.width), height: mapping.viewLength(fromContent: box.height),
                rotation: annotation.rotation)
        }
    }

    /// Handles of a single selected annotation (none for a multi-selection).
    public func selectionHandles(viewWidth: Double, viewHeight: Double) -> [HandleMark] {
        let ids = annotationSelection
        guard ids.count == 1, let id = ids.first, let annotation = session.annotations.annotation(id),
            let mapping = annotationMapping(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return [] }
        let offset = mapping.contentLength(fromView: AnnotationDefaults.rotateHandleOffset)
        return annotation.handles(rotateOffset: offset).map {
            let point = mapping.viewPoint(fromContent: $0.point)
            return HandleMark(handle: $0.handle, x: point.x, y: point.y)
        }
    }

    /// Where the open text editor sits (top-left, view points) and its font size in view points.
    public func textEditorPlacement(viewWidth: Double, viewHeight: Double) -> (x: Double, y: Double, fontSize: Double)?
    {
        guard let editing = annotate.textEditing,
            let mapping = annotationMapping(viewWidth: viewWidth, viewHeight: viewHeight)
        else { return nil }
        let point = mapping.viewPoint(fromContent: editing.point)
        let fontSize =
            editing.id.flatMap { session.annotations.annotation($0)?.fontSize }
            ?? annotate.style.fontSize(longEdge: mapping.contentLongEdge)
        return (point.x, point.y, mapping.viewLength(fromContent: fontSize))
    }
}
