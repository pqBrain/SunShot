public import Foundation
public import Observation
public import SunshotCore

/// Annotate-mode editor state: tool, drawing style, selection, the drag in progress and the open text editor.
/// None of this is document state (selection never makes an undo entry); document edits go through `EditorModel`.
@MainActor
@Observable
public final class AnnotationEditor {
    /// Text being typed for a new text annotation (`id` nil) or an existing one.
    public struct TextEditing: Equatable, Sendable {
        public var point: AnnotationPoint
        public var id: UUID?
        public var text: String
    }

    public internal(set) var isActive = false
    public internal(set) var tool: AnnotationTool = .pen
    public internal(set) var style = AnnotationStyle()
    /// Raw selection; read `EditorModel.annotationSelection`, which drops ids that no longer exist (after undo).
    public internal(set) var selection: Set<UUID> = []
    public internal(set) var drag: AnnotationDrag?
    public var textEditing: TextEditing?
    public var showsStickerPicker = false

    public init() {}

    public var isDragging: Bool { drag != nil }
}
