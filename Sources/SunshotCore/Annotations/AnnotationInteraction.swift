public import Foundation

/// Undo entry names of annotation edits.
public enum AnnotationAction {
    public static let move = "Move Annotation"
    public static let resize = "Resize Annotation"
    public static let rotate = "Rotate Annotation"
    public static let erase = "Erase"
    public static let duplicate = "Duplicate Annotation"
    public static let delete = "Delete Annotation"
    public static let clear = "Clear Annotations"
    public static let editText = "Edit Text"
    public static let style = "Change Annotation Style"
    public static let stepFormat = "Change Step Format"

    /// Name of the entry that adds an annotation of `kind`.
    public static func add(_ kind: AnnotationKind) -> String {
        switch kind {
        case .pen: "Draw"
        case .highlighter: "Highlight"
        case .arrow: "Add Arrow"
        case .rectangle: "Add Rectangle"
        case .text: "Add Text"
        case .step: "Add Step"
        case .redact: "Add Redaction"
        case .sticker: "Add Sticker"
        }
    }
}

/// What a pointer press starts.
public enum AnnotationPress: Sendable {
    /// Nothing to do (e.g. a click on empty space, or a ⌘-click that only changed the selection).
    case none
    /// A continuous drag; feed it pointer positions and record it as one undo entry.
    case drag(AnnotationDrag)
    /// Add this annotation right away (steps and stickers are placed by a click).
    case place(Annotation)
    /// Open the text editor at `point`, for a new text or for the existing text annotation `id`.
    case editText(at: AnnotationPoint, id: UUID?)
}

/// Pointer-press logic for Annotate mode (pure). Distances are content pixels.
public enum AnnotationInteraction {
    public struct Context: Sendable {
        public var tool: AnnotationTool
        public var style: AnnotationStyle
        public var layer: AnnotationLayer
        public var selection: Set<UUID>
        /// Long edge of the content in pixels (sizes S/M/L scale with it).
        public var longEdge: Double
        /// Hit tolerance, handle radius and rotate-handle offset, already converted to content pixels.
        public var tolerance: Double
        public var rotateOffset: Double

        public init(
            tool: AnnotationTool, style: AnnotationStyle, layer: AnnotationLayer, selection: Set<UUID>,
            longEdge: Double, tolerance: Double, rotateOffset: Double
        ) {
            self.tool = tool
            self.style = style
            self.layer = layer
            self.selection = selection
            self.longEdge = longEdge
            self.tolerance = tolerance
            self.rotateOffset = rotateOffset
        }
    }

    /// Handles a press at `point`. `additive` is ⌘-click. Returns what to do and the new selection.
    public static func press(
        at point: AnnotationPoint, additive: Bool, in context: Context
    ) -> (press: AnnotationPress, selection: Set<UUID>) {
        let layer = context.layer
        let selection = layer.existing(context.selection)
        switch context.tool {
        case .select:
            return pressSelect(at: point, additive: additive, selection: selection, context: context)
        case .eraser:
            var drag = AnnotationDrag(mode: .erase, base: layer, start: point, tolerance: context.tolerance)
            drag.update(to: point)
            return (.drag(drag), [])
        case .text:
            if let hit = layer.topmost(at: point, tolerance: context.tolerance), hit.kind == .text {
                return (.editText(at: AnnotationPoint(x: hit.bounds.x, y: hit.bounds.y), id: hit.id), [])
            }
            return (.editText(at: point, id: nil), [])
        case .step, .sticker:
            let kind: AnnotationKind = context.tool == .step ? .step : .sticker
            return (.place(.make(kind, from: point, to: point, style: context.style, longEdge: context.longEdge)), [])
        case .pen, .highlighter, .arrow, .rectangle, .redact:
            guard let kind = context.tool.kind else { return (.none, selection) }
            let annotation = Annotation.make(
                kind, from: point, to: point, style: context.style, longEdge: context.longEdge)
            let drag = AnnotationDrag(
                mode: .create(annotation), base: layer, start: point, tolerance: context.tolerance)
            return (.drag(drag), [])
        }
    }

    private static func pressSelect(
        at point: AnnotationPoint, additive: Bool, selection: Set<UUID>, context: Context
    ) -> (press: AnnotationPress, selection: Set<UUID>) {
        let layer = context.layer
        if !additive, selection.count == 1, let id = selection.first, let selected = layer.annotation(id),
            let handle = selected.handle(
                at: point, tolerance: context.tolerance, rotateOffset: context.rotateOffset)
        {
            let mode: AnnotationDrag.Mode =
                switch handle {
                case .corner(let corner): .resize(id, corner)
                case .rotate: .rotate(id)
                case .endpoint(let index): .endpoint(id, index)
                }
            return (
                .drag(AnnotationDrag(mode: mode, base: layer, start: point, tolerance: context.tolerance)), selection
            )
        }
        guard let hit = layer.topmost(at: point, tolerance: context.tolerance) else {
            return (.none, additive ? selection : [])
        }
        if additive {
            return (.none, selection.symmetricDifference([hit.id]))
        }
        let moving = selection.contains(hit.id) ? selection : [hit.id]
        return (
            .drag(AnnotationDrag(mode: .move(moving), base: layer, start: point, tolerance: context.tolerance)), moving
        )
    }
}

/// One pointer drag in Annotate mode. Each `update` recomputes `layer` from the state at the press,
/// so the whole drag is one undo entry and never accumulates rounding.
public struct AnnotationDrag: Sendable {
    public enum Mode: Sendable {
        case create(Annotation)
        case move(Set<UUID>)
        case resize(UUID, AnnotationCorner)
        case endpoint(UUID, Int)
        case rotate(UUID)
        case erase
    }

    public let mode: Mode
    public let base: AnnotationLayer
    public let start: AnnotationPoint
    public private(set) var layer: AnnotationLayer
    private let tolerance: Double
    private var path: [AnnotationPoint]
    private var last: AnnotationPoint

    public init(mode: Mode, base: AnnotationLayer, start: AnnotationPoint, tolerance: Double) {
        self.mode = mode
        self.base = base
        self.start = start
        self.tolerance = max(0, tolerance)
        layer = base
        path = [start]
        last = start
        if case .create(let annotation) = mode, annotation.kind == .pen || annotation.kind == .highlighter {
            layer.add(annotation)
        }
    }

    /// Undo entry name for this drag.
    public var actionName: String {
        switch mode {
        case .create(let annotation): AnnotationAction.add(annotation.kind)
        case .move: AnnotationAction.move
        case .resize, .endpoint: AnnotationAction.resize
        case .rotate: AnnotationAction.rotate
        case .erase: AnnotationAction.erase
        }
    }

    /// The pointer moved to `point`. `snap` (⇧) snaps rotation to 15° steps.
    public mutating func update(to point: AnnotationPoint, snap: Bool = false) {
        defer { last = point }
        switch mode {
        case .create(var annotation):
            if annotation.kind == .pen || annotation.kind == .highlighter {
                if let previous = path.last, previous.distance(to: point) >= 0.5 { path.append(point) }
                annotation.points = path
                layer = base
                layer.add(annotation)
            } else if start.distance(to: point) < max(tolerance, 2) {
                layer = base
            } else {
                annotation.points = [start, point]
                layer = base
                layer.add(annotation)
            }
        case .move(let ids):
            layer = base
            layer.translate(ids, by: point - start)
        case .resize(let id, let corner):
            guard let original = base.annotation(id) else { return }
            layer = base
            layer.replace(original.resized(corner: corner, to: point))
        case .endpoint(let id, let index):
            guard var original = base.annotation(id), original.points.indices.contains(index) else { return }
            original.points[index] = point
            layer = base
            layer.replace(original)
        case .rotate(let id):
            guard var original = base.annotation(id) else { return }
            original.rotation = Annotation.rotation(
                original: original.rotation, center: original.center, start: start, point: point, snap: snap)
            layer = base
            layer.replace(original)
        case .erase:
            erase(from: last, to: point)
        }
    }

    /// Removes every annotation the eraser passes over between two samples (sampled every half tolerance).
    private mutating func erase(from: AnnotationPoint, to: AnnotationPoint) {
        let step = max(1, tolerance / 2)
        let count = max(1, Int((from.distance(to: to) / step).rounded(.up)))
        var hit = Set<UUID>()
        for index in 0...count {
            let t = Double(index) / Double(count)
            let sample = AnnotationPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            hit.formUnion(layer.ids(at: sample, tolerance: tolerance))
        }
        layer.remove(hit)
    }
}
