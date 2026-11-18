public import Foundation

/// A point in content-pixel coordinates: origin at the top-left of the unscaled content image, y down.
/// Annotations live in this space so they stay attached to the content whatever the canvas, padding or scaling.
public struct AnnotationPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
    }

    public static func + (lhs: AnnotationPoint, rhs: AnnotationPoint) -> AnnotationPoint {
        AnnotationPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: AnnotationPoint, rhs: AnnotationPoint) -> AnnotationPoint {
        AnnotationPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public func distance(to other: AnnotationPoint) -> Double { hypot(x - other.x, y - other.y) }

    /// This point rotated by `degrees` (clockwise on screen, since y points down) about `center`.
    public func rotated(by degrees: Double, around center: AnnotationPoint) -> AnnotationPoint {
        guard degrees != 0 else { return self }
        let radians = degrees * .pi / 180
        let (sine, cosine) = (sin(radians), cos(radians))
        let dx = x - center.x
        let dy = y - center.y
        return AnnotationPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
    }
}

/// What an annotation is. Raw values are the persisted names; an unknown name makes that annotation skipped.
public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case pen, highlighter, arrow, rectangle, text, step, redact, sticker

    /// Kinds that resize uniformly (their aspect ratio is fixed).
    public var keepsAspect: Bool { self == .text || self == .step || self == .sticker }
}

public enum AnnotationLineStyle: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted
}

public enum RedactionMode: String, Codable, CaseIterable, Sendable {
    case pixelate, blur
}

public enum AnnotationTextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// One vector annotation. A flat value type: `points` carries the geometry for every kind —
/// the path for pen/highlighter, `[start, end]` for arrows, and two opposite corners for boxed kinds.
public struct Annotation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: AnnotationKind
    public var points: [AnnotationPoint]
    public var color: RGBAColor
    /// Stroke width in content pixels (also drives arrow heads and redaction block size).
    public var lineWidth: Double
    public var lineStyle: AnnotationLineStyle
    /// Rectangles: filled instead of outlined.
    public var filled: Bool
    /// Degrees, clockwise on screen, about the centre of `bounds`.
    public var rotation: Double
    /// Text content, or the emoji of a sticker.
    public var text: String
    /// Text annotations: font size in content pixels.
    public var fontSize: Double
    public var alignment: AnnotationTextAlignment
    public var redaction: RedactionMode

    public init(
        id: UUID = UUID(), kind: AnnotationKind, points: [AnnotationPoint], color: RGBAColor = AnnotationDefaults.color,
        lineWidth: Double = AnnotationSize.medium.baseWidth, lineStyle: AnnotationLineStyle = .solid,
        filled: Bool = false, rotation: Double = 0, text: String = "", fontSize: Double = 24,
        alignment: AnnotationTextAlignment = .left, redaction: RedactionMode = .pixelate
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth.isFinite ? max(0.5, lineWidth) : AnnotationSize.medium.baseWidth
        self.lineStyle = lineStyle
        self.filled = filled
        self.rotation = rotation.isFinite ? rotation : 0
        self.text = text
        self.fontSize = fontSize.isFinite ? max(1, fontSize) : 24
        self.alignment = alignment
        self.redaction = redaction
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, points, color, lineWidth, lineStyle, filled, rotation, text, fontSize, alignment, redaction
    }

    /// Tolerant: only `kind` is required (an unknown kind throws, and the layer skips that annotation);
    /// every other missing or unreadable field takes its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(AnnotationKind.self, forKey: .kind)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init(
            id: value(.id, UUID()), kind: kind, points: value(.points, []),
            color: value(.color, AnnotationDefaults.color),
            lineWidth: value(.lineWidth, AnnotationSize.medium.baseWidth), lineStyle: value(.lineStyle, .solid),
            filled: value(.filled, false), rotation: value(.rotation, 0), text: value(.text, ""),
            fontSize: value(.fontSize, 24), alignment: value(.alignment, .left), redaction: value(.redaction, .pixelate)
        )
    }

    /// Enough points for its kind (pen and highlighter need one, everything else two).
    public var isValid: Bool {
        switch kind {
        case .pen, .highlighter: !points.isEmpty
        default: points.count >= 2
        }
    }
}

// MARK: Geometry

extension Annotation {
    /// Unrotated bounding box of the geometry (no stroke width), in content pixels.
    public var bounds: LayoutRect {
        guard let first = points.first else { return LayoutRect(x: 0, y: 0, width: 0, height: 0) }
        var (minX, minY, maxX, maxY) = (first.x, first.y, first.x, first.y)
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return LayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public var center: AnnotationPoint { AnnotationPoint(x: bounds.midX, y: bounds.midY) }

    /// Moved by `offset`.
    public func translated(by offset: AnnotationPoint) -> Annotation {
        var copy = self
        copy.points = points.map { $0 + offset }
        return copy
    }

    /// Geometry mapped from the rectangle `from` onto `to` (unrotated frame). Text scales its font with the height.
    public func mapped(from: LayoutRect, to: LayoutRect) -> Annotation {
        let scaleX = from.width > 0 ? to.width / from.width : 1
        let scaleY = from.height > 0 ? to.height / from.height : 1
        var copy = self
        copy.points = points.map {
            AnnotationPoint(x: to.x + ($0.x - from.x) * scaleX, y: to.y + ($0.y - from.y) * scaleY)
        }
        if kind == .text { copy.fontSize = max(1, fontSize * scaleY) }
        return copy
    }

    /// A point in content space expressed in this annotation's unrotated frame.
    public func localPoint(_ point: AnnotationPoint) -> AnnotationPoint {
        point.rotated(by: -rotation, around: center)
    }

    /// A point of the unrotated frame expressed in content space.
    public func worldPoint(_ point: AnnotationPoint) -> AnnotationPoint {
        point.rotated(by: rotation, around: center)
    }

    /// Whether `point` (content space) touches the annotation, allowing `tolerance` content pixels.
    public func contains(_ point: AnnotationPoint, tolerance: Double) -> Bool {
        let local = localPoint(point)
        let box = bounds
        switch kind {
        case .pen, .highlighter:
            return AnnotationGeometry.distance(from: local, toPolyline: points) <= lineWidth / 2 + tolerance
        case .arrow:
            let reach = max(lineWidth / 2, AnnotationGeometry.arrowHeadLength(lineWidth: lineWidth) / 2)
            return AnnotationGeometry.distance(from: local, toPolyline: points) <= reach + tolerance
        case .rectangle where !filled:
            let inner = AnnotationGeometry.inset(box, by: lineWidth / 2 + tolerance)
            let outer = AnnotationGeometry.inset(box, by: -(lineWidth / 2 + tolerance))
            return AnnotationGeometry.rect(outer, contains: local) && !AnnotationGeometry.rect(inner, contains: local)
        case .step:
            return local.distance(to: center) <= min(box.width, box.height) / 2 + tolerance
        case .rectangle, .text, .redact, .sticker:
            return AnnotationGeometry.rect(AnnotationGeometry.inset(box, by: -tolerance), contains: local)
        }
    }
}
