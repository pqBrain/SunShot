public import Foundation

/// All annotations of a document, back to front, plus document-wide annotation settings.
public struct AnnotationLayer: Codable, Hashable, Sendable {
    public var items: [Annotation]
    public var stepFormat: StepFormat

    public init(items: [Annotation] = [], stepFormat: StepFormat = .numbers) {
        self.items = items
        self.stepFormat = stepFormat
    }

    enum CodingKeys: String, CodingKey {
        case items, stepFormat
    }

    /// Tolerant: annotations that can't be decoded (unknown kind, too few points) are skipped, missing keys default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = (try? container.decodeIfPresent([Lossy].self, forKey: .items)) ?? nil
        items = (lossy ?? []).compactMap(\.value).filter(\.isValid)
        stepFormat = ((try? container.decodeIfPresent(StepFormat.self, forKey: .stepFormat)) ?? nil) ?? .numbers
    }

    /// Decodes one element without failing the array.
    private struct Lossy: Decodable {
        let value: Annotation?
        init(from decoder: any Decoder) throws { value = try? Annotation(from: decoder) }
    }

    public var isEmpty: Bool { items.isEmpty }

    public func annotation(_ id: UUID) -> Annotation? { items.first { $0.id == id } }

    /// Ids of the annotations that still exist, in back-to-front order.
    public func existing(_ ids: Set<UUID>) -> Set<UUID> { Set(items.map(\.id).filter(ids.contains)) }

    // MARK: Hit-testing

    /// The topmost annotation touching `point` (content px), allowing `tolerance` content px.
    public func topmost(at point: AnnotationPoint, tolerance: Double) -> Annotation? {
        items.last { $0.contains(point, tolerance: tolerance) }
    }

    /// Every annotation touching `point`.
    public func ids(at point: AnnotationPoint, tolerance: Double) -> Set<UUID> {
        Set(items.filter { $0.contains(point, tolerance: tolerance) }.map(\.id))
    }

    // MARK: Steps

    /// Label of a step annotation: its position among the steps, back to front, in the layer's format.
    public func stepLabel(for id: UUID) -> String? {
        let steps = items.filter { $0.kind == .step }
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
        return stepFormat.label(index)
    }

    // MARK: Edits (pure; the document store records them)

    public mutating func add(_ annotation: Annotation) {
        guard annotation.isValid else { return }
        items.append(annotation)
    }

    public mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    public mutating func translate(_ ids: Set<UUID>, by offset: AnnotationPoint) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index] = items[index].translated(by: offset)
        }
    }

    public mutating func replace(_ annotation: Annotation) {
        guard let index = items.firstIndex(where: { $0.id == annotation.id }) else { return }
        items[index] = annotation
    }

    /// Changes every annotation in `ids`.
    public mutating func update(_ ids: Set<UUID>, _ change: (inout Annotation) -> Void) {
        for index in items.indices where ids.contains(items[index].id) {
            change(&items[index])
        }
    }

    /// Copies `ids` (in z-order, on top of everything) moved by `offset`. Returns the ids of the copies.
    @discardableResult
    public mutating func duplicate(_ ids: Set<UUID>, offset: AnnotationPoint) -> Set<UUID> {
        let copies = items.filter { ids.contains($0.id) }.map { original -> Annotation in
            var copy = original.translated(by: offset)
            copy.id = UUID()
            return copy
        }
        items.append(contentsOf: copies)
        return Set(copies.map(\.id))
    }
}

extension Annotation {
    /// A new annotation of `kind` spanning `start`…`end` with the current `style`, sized for content whose long edge
    /// is `longEdge` pixels. Click-placed kinds (step, sticker) are centred on `start`; text starts there.
    public static func make(
        _ kind: AnnotationKind, from start: AnnotationPoint, to end: AnnotationPoint, style: AnnotationStyle,
        longEdge: Double, text: String = ""
    ) -> Annotation {
        var points = [start, end]
        var content = text
        let fontSize = style.fontSize(longEdge: longEdge)
        switch kind {
        case .pen, .highlighter:
            points = start == end ? [start] : [start, end]
        case .step:
            points = centredSquare(at: start, side: style.stepDiameter(longEdge: longEdge))
        case .sticker:
            points = centredSquare(at: start, side: style.stickerSize(longEdge: longEdge))
            content = style.sticker
        case .text:
            let size = TextMetrics.estimatedSize(of: text, fontSize: fontSize)
            points = [start, AnnotationPoint(x: start.x + size.width, y: start.y + size.height)]
        case .arrow, .rectangle, .redact:
            break
        }
        return Annotation(
            kind: kind, points: points, color: style.color, lineWidth: style.lineWidth(for: kind, longEdge: longEdge),
            lineStyle: style.lineStyle, filled: style.filled, text: content, fontSize: fontSize,
            alignment: style.alignment, redaction: style.redaction)
    }

    private static func centredSquare(at center: AnnotationPoint, side: Double) -> [AnnotationPoint] {
        [
            AnnotationPoint(x: center.x - side / 2, y: center.y - side / 2),
            AnnotationPoint(x: center.x + side / 2, y: center.y + side / 2),
        ]
    }

    /// Replaces the text of a text annotation and refits its box (top-left stays, rotation kept).
    public func withText(_ newText: String) -> Annotation {
        var copy = self
        copy.text = newText
        guard kind == .text else { return copy }
        let origin = AnnotationPoint(x: bounds.x, y: bounds.y)
        let size = TextMetrics.estimatedSize(of: newText, fontSize: fontSize)
        copy.points = [origin, AnnotationPoint(x: origin.x + size.width, y: origin.y + size.height)]
        return copy
    }
}

/// Text box estimate used for hit-testing and selection (the renderer lays text out with CoreText inside it).
public enum TextMetrics {
    public static let lineHeightFactor: Double = 1.25
    public static let averageAdvanceFactor: Double = 0.6

    public static func estimatedSize(of text: String, fontSize: Double) -> (width: Double, height: Double) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        let width = max(fontSize, Double(longest) * fontSize * averageAdvanceFactor + fontSize * 0.2)
        let height = Double(max(1, lines.count)) * fontSize * lineHeightFactor
        return (width, height)
    }
}
