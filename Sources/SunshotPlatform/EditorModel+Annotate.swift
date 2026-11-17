public import Foundation
public import SunshotCore
import SunshotRender

/// A key typed while the annotation canvas has focus.
public enum AnnotateKey: Equatable, Sendable {
    case character(Character)
    case escape
    case delete
}

/// Annotate mode (S9): entering/leaving, tools and style, pointer handling and selection commands.
/// Views pass view-space points of the displayed canvas; all maths lives in `ContentMapping` / `AnnotationInteraction`.
extension EditorModel {
    /// Annotating needs image content shown flat: pointer mapping (S9 `ContentMapping`) doesn't yet invert the S6
    /// position / zoom / rotation / tilt, and code snippets (S11) are drawn at output density (see DECISIONS, integration notes).
    /// S12: nor the crop of a device screen, so device mockups can't be annotated either.
    public var canAnnotate: Bool {
        session.document.content != nil && session.document.project.placement.transform.isIdentity
            && session.document.project.frame.device == nil
    }

    public var hasAnnotations: Bool { !session.annotations.isEmpty }

    public var stepFormat: StepFormat { session.annotations.stepFormat }

    /// Selected annotations that still exist (undo can remove them).
    public var annotationSelection: Set<UUID> { session.annotations.existing(annotate.selection) }

    public func setAnnotateMode(_ active: Bool) {
        guard active != annotate.isActive else { return }
        if active {
            guard canAnnotate else { return }
            annotate.isActive = true
        } else {
            commitTextEditing()
            endAnnotationDrag()
            annotate.selection = []
            annotate.showsStickerPicker = false
            annotate.isActive = false
        }
    }

    public func toggleAnnotateMode() { setAnnotateMode(!annotate.isActive) }

    public func selectTool(_ tool: AnnotationTool) {
        commitTextEditing()
        annotate.tool = tool
        if tool != .select { annotate.selection = [] }
    }

    /// Picks an emoji and switches to the sticker tool.
    public func chooseSticker(_ emoji: String) {
        annotate.style.sticker = emoji
        annotate.showsStickerPicker = false
        selectTool(.sticker)
    }

    // MARK: Style (applies to the selection too, as one undo step)

    public func setAnnotationColor(_ color: RGBAColor) {
        annotate.style.color = color
        let ids = annotationSelection
        guard !ids.isEmpty else { return }
        performContinuous(AnnotationAction.style) { $0.restyleAnnotations(ids) { $0.color = color } }
    }

    public func setAnnotationSize(_ size: AnnotationSize) {
        annotate.style.size = size
        let style = annotate.style
        let longEdge = session.contentLongEdge
        restyleSelection { annotation in
            annotation.lineWidth = style.lineWidth(for: annotation.kind, longEdge: longEdge)
            if annotation.kind == .text { annotation = annotation.resizedFont(style.fontSize(longEdge: longEdge)) }
        }
    }

    public func setAnnotationLineStyle(_ lineStyle: AnnotationLineStyle) {
        annotate.style.lineStyle = lineStyle
        restyleSelection { $0.lineStyle = lineStyle }
    }

    public func setAnnotationFilled(_ filled: Bool) {
        annotate.style.filled = filled
        restyleSelection { $0.filled = filled }
    }

    public func setRedactionMode(_ mode: RedactionMode) {
        annotate.style.redaction = mode
        restyleSelection { $0.redaction = mode }
    }

    public func setTextAlignment(_ alignment: AnnotationTextAlignment) {
        annotate.style.alignment = alignment
        restyleSelection { $0.alignment = alignment }
    }

    public func setStepFormat(_ format: StepFormat) { perform { $0.setStepFormat(format) } }

    private func restyleSelection(_ change: @escaping (inout Annotation) -> Void) {
        let ids = annotationSelection
        guard !ids.isEmpty else { return }
        perform { $0.restyleAnnotations(ids, change) }
    }

    // MARK: Keys

    /// Tool letters, `[` `]` size, ⇧1–3 line style, F fill, ⌫ delete, Esc (closes the text editor, else leaves the
    /// mode). Returns whether the key was used.
    @discardableResult
    public func handleAnnotateKey(_ key: AnnotateKey, shift: Bool = false) -> Bool {
        guard annotate.isActive, annotate.textEditing == nil else {
            if key == .escape, annotate.textEditing != nil {
                annotate.textEditing = nil
                return true
            }
            return false
        }
        switch key {
        case .escape:
            setAnnotateMode(false)
        case .delete:
            deleteSelectedAnnotations()
        case .character(let character):
            return handleAnnotateCharacter(character, shift: shift)
        }
        return true
    }

    private func handleAnnotateCharacter(_ character: Character, shift: Bool) -> Bool {
        switch character {
        case "[": setAnnotationSize(annotate.style.size.stepped(by: -1))
        case "]": setAnnotationSize(annotate.style.size.stepped(by: 1))
        case "!": setAnnotationLineStyle(.solid)
        case "@": setAnnotationLineStyle(.dashed)
        case "#": setAnnotationLineStyle(.dotted)
        case "1" where shift: setAnnotationLineStyle(.solid)
        case "2" where shift: setAnnotationLineStyle(.dashed)
        case "3" where shift: setAnnotationLineStyle(.dotted)
        case "f", "F": setAnnotationFilled(!annotate.style.filled)
        default:
            guard let tool = AnnotationTool.forShortcut(character) else { return false }
            selectTool(tool)
        }
        return true
    }

    // MARK: Commands

    public func deleteSelectedAnnotations() {
        let ids = annotationSelection
        guard !ids.isEmpty else { return }
        perform { $0.deleteAnnotations(ids) }
        annotate.selection = []
    }

    public func duplicateSelectedAnnotations() {
        let ids = annotationSelection
        guard !ids.isEmpty else { return }
        var copies = Set<UUID>()
        perform { copies = $0.duplicateAnnotations(ids) }
        annotate.selection = copies
    }

    public func clearAnnotations() {
        perform { $0.clearAnnotations() }
        annotate.selection = []
    }

    /// ⌘⌫: clears the annotations in Annotate mode, the content otherwise.
    public var clearCommandTitle: String { annotate.isActive ? UIStrings.clearAnnotations : UIStrings.clearContent }

    public var canClear: Bool { annotate.isActive ? hasAnnotations : hasContent }

    public func clearCommand() async {
        if annotate.isActive {
            clearAnnotations()
        } else {
            await clearContent()
        }
    }

    // MARK: Text

    /// Commits the open text editor (empty text adds nothing). No-op when none is open.
    public func commitTextEditing() {
        guard let editing = annotate.textEditing else { return }
        annotate.textEditing = nil
        let style = annotate.style
        perform { $0.commitText(editing.text, at: editing.point, id: editing.id, style: style) }
    }

    public func cancelTextEditing() { annotate.textEditing = nil }
}

extension Annotation {
    /// A text annotation at a new font size, its box refitted.
    func resizedFont(_ size: Double) -> Annotation {
        var copy = self
        copy.fontSize = size
        return copy.withText(text)
    }
}
