import Foundation

/// Pure geometry helpers for annotations (content-pixel space).
public enum AnnotationGeometry {
    /// Arrow head length for a shaft of `lineWidth`: grows with the width, never smaller than 10 px.
    public static func arrowHeadLength(lineWidth: Double) -> Double { max(10, lineWidth * 4) }

    /// Shortest distance from `point` to the polyline through `points` (a single point is a dot).
    public static func distance(from point: AnnotationPoint, toPolyline points: [AnnotationPoint]) -> Double {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return point.distance(to: first) }
        var best = Double.infinity
        for index in 1..<points.count {
            best = min(best, distance(from: point, toSegment: points[index - 1], points[index]))
        }
        return best
    }

    public static func distance(
        from point: AnnotationPoint, toSegment start: AnnotationPoint, _ end: AnnotationPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return point.distance(to: start) }
        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return point.distance(to: AnnotationPoint(x: start.x + t * dx, y: start.y + t * dy))
    }

    /// `rect` shrunk by `amount` on every side (grown when negative); never negative in size.
    public static func inset(_ rect: LayoutRect, by amount: Double) -> LayoutRect {
        LayoutRect(
            x: rect.x + amount, y: rect.y + amount, width: max(0, rect.width - amount * 2),
            height: max(0, rect.height - amount * 2))
    }

    public static func rect(_ rect: LayoutRect, contains point: AnnotationPoint) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height
    }

    /// Normalised rectangle spanning two points.
    public static func rect(from a: AnnotationPoint, to b: AnnotationPoint) -> LayoutRect {
        LayoutRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public static func corner(_ corner: AnnotationCorner, of rect: LayoutRect) -> AnnotationPoint {
        switch corner {
        case .topLeft: AnnotationPoint(x: rect.x, y: rect.y)
        case .topRight: AnnotationPoint(x: rect.x + rect.width, y: rect.y)
        case .bottomLeft: AnnotationPoint(x: rect.x, y: rect.y + rect.height)
        case .bottomRight: AnnotationPoint(x: rect.x + rect.width, y: rect.y + rect.height)
        }
    }

    /// Smallest box (content px) a resize may produce, so objects can't collapse to nothing.
    public static let minimumSize: Double = 4
}

public enum AnnotationCorner: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var opposite: AnnotationCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }
}

/// A grab point on a selected annotation.
public enum AnnotationHandle: Hashable, Sendable {
    case corner(AnnotationCorner)
    case rotate
    /// Arrow endpoint: 0 = start, 1 = end.
    case endpoint(Int)
}

extension Annotation {
    /// Handles in content space. `rotateOffset` is how far above the top edge the rotate handle sits (content px).
    public func handles(rotateOffset: Double) -> [(handle: AnnotationHandle, point: AnnotationPoint)] {
        if kind == .arrow {
            return points.prefix(2).enumerated().map { (.endpoint($0.offset), $0.element) }
        }
        let box = bounds
        var result: [(handle: AnnotationHandle, point: AnnotationPoint)] = AnnotationCorner.allCases.map {
            (.corner($0), worldPoint(AnnotationGeometry.corner($0, of: box)))
        }
        result.append((.rotate, worldPoint(AnnotationPoint(x: box.midX, y: box.y - rotateOffset))))
        return result
    }

    /// The handle under `point`, if any (within `tolerance` content px).
    public func handle(at point: AnnotationPoint, tolerance: Double, rotateOffset: Double) -> AnnotationHandle? {
        handles(rotateOffset: rotateOffset).first { $0.point.distance(to: point) <= tolerance }?.handle
    }

    /// Resized by dragging the `corner` handle to `point` (content space). The opposite corner stays where it is on
    /// screen, also when rotated. Kinds with a fixed aspect resize uniformly.
    public func resized(corner: AnnotationCorner, to point: AnnotationPoint) -> Annotation {
        let box = bounds
        let anchor = AnnotationGeometry.corner(corner.opposite, of: box)
        let anchorOnScreen = worldPoint(anchor)
        let local = localPoint(point)
        var width = max(AnnotationGeometry.minimumSize, abs(local.x - anchor.x))
        var height = max(AnnotationGeometry.minimumSize, abs(local.y - anchor.y))
        if kind.keepsAspect, box.width > 0, box.height > 0 {
            let factor = max(width / box.width, height / box.height)
            width = box.width * factor
            height = box.height * factor
        }
        let signX: Double = local.x >= anchor.x ? 1 : -1
        let signY: Double = local.y >= anchor.y ? 1 : -1
        let target = AnnotationGeometry.rect(
            from: anchor, to: AnnotationPoint(x: anchor.x + signX * width, y: anchor.y + signY * height))
        var result = mapped(from: box, to: target)
        // Rotation is about the (new) centre; shift so the anchor keeps its on-screen position.
        let drift = anchorOnScreen - result.worldPoint(anchor)
        result = result.translated(by: drift)
        return result
    }

    /// Rotation after dragging the rotate handle from `start` to `point`, from `original` degrees.
    /// `snap` rounds to 15° steps. Normalised to −180…180.
    public static func rotation(
        original: Double, center: AnnotationPoint, start: AnnotationPoint, point: AnnotationPoint, snap: Bool
    ) -> Double {
        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let angle = atan2(point.y - center.y, point.x - center.x)
        var degrees = original + (angle - startAngle) * 180 / .pi
        if snap { degrees = (degrees / 15).rounded() * 15 }
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 { degrees -= 360 }
        if degrees <= -180 { degrees += 360 }
        return degrees
    }
}
