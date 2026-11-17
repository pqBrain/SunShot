import Foundation

/// A point in canvas pixels, origin at the top-left, y down.
public struct LayoutPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Maps the laid-out content through a `ContentTransform` onto the canvas.
///
/// Local coordinates are the content's own: origin at its top-left, in canvas pixels before zoom
/// (`0…contentRect.width` × `0…contentRect.height`). Order: zoom about the centre, rotate in the plane
/// (positive = clockwise on screen), tilt about the vertical axis (`tiltY`), tilt about the horizontal axis
/// (`tiltX`), then a perspective projection from a camera `perspectiveDistance` in front of the content, and
/// finally the offset. With no tilt this is exactly the affine `center · rotate · scale · −halfSize` map.
public struct ContentProjection: Sendable {
    public let contentSize: (width: Double, height: Double)
    public let center: LayoutPoint
    public let transform: ContentTransform
    /// Camera distance in canvas pixels: `perspectiveFactor` × the zoomed content's longer side.
    public let perspectiveDistance: Double
    private let cosR: Double, sinR: Double
    private let cosY: Double, sinY: Double
    private let cosX: Double, sinX: Double

    public init(contentRect: LayoutRect, canvasSize: PixelSize, transform: ContentTransform) {
        let width = contentRect.width.isFinite ? max(contentRect.width, 0) : 0
        let height = contentRect.height.isFinite ? max(contentRect.height, 0) : 0
        contentSize = (width, height)
        self.transform = transform
        center = LayoutPoint(
            x: contentRect.midX + transform.x * Double(canvasSize.width),
            y: contentRect.midY + transform.y * Double(canvasSize.height))
        perspectiveDistance = max(max(width, height) * transform.scale * ContentTransform.perspectiveFactor, 1)
        let radians = { (degrees: Double) in degrees * .pi / 180 }
        (cosR, sinR) = (cos(radians(transform.rotation)), sin(radians(transform.rotation)))
        (cosY, sinY) = (cos(radians(transform.tiltY)), sin(radians(transform.tiltY)))
        (cosX, sinX) = (cos(radians(transform.tiltX)), sin(radians(transform.tiltX)))
    }

    /// Projects a local content point onto the canvas. Always finite: the camera is further away than any
    /// point of the content can come (`perspectiveFactor` > half the diagonal / longer side).
    public func project(_ local: LayoutPoint) -> LayoutPoint {
        let scale = transform.scale
        let px = (local.x - contentSize.width / 2) * scale
        let py = (local.y - contentSize.height / 2) * scale
        // In-plane rotation.
        let rx = px * cosR - py * sinR
        let ry = px * sinR + py * cosR
        // Tilt about the vertical axis: positive pushes the right side away (z toward the viewer is positive).
        let x1 = rx * cosY
        let z1 = -rx * sinY
        // Tilt about the horizontal axis: positive pushes the top (negative y) away.
        let y2 = ry * cosX - z1 * sinX
        let z2 = ry * sinX + z1 * cosX
        let factor = perspectiveDistance / max(perspectiveDistance - z2, 1e-6)
        return LayoutPoint(x: center.x + x1 * factor, y: center.y + y2 * factor)
    }

    /// The content's corners on the canvas: top-left, top-right, bottom-right, bottom-left (local orientation).
    public var corners: [LayoutPoint] { quad(insetBy: 0) }

    /// Corners of the local rect grown by `outset` local pixels on every side (for anti-aliasing margins).
    public func quad(insetBy outset: Double) -> [LayoutPoint] {
        let (width, height) = contentSize
        return [
            LayoutPoint(x: -outset, y: -outset), LayoutPoint(x: width + outset, y: -outset),
            LayoutPoint(x: width + outset, y: height + outset), LayoutPoint(x: -outset, y: height + outset),
        ].map(project)
    }

    /// Axis-aligned bounds of the projected content.
    public var bounds: LayoutRect { Self.bounds(of: corners) }

    public static func bounds(of points: [LayoutPoint]) -> LayoutRect {
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

    /// Projected content area (the quad is convex, so the shoelace formula is exact).
    public var area: Double { Self.area(of: corners) }

    /// Share of the projected content area that lies on the canvas (0…1).
    public func visibleFraction(canvasSize: PixelSize) -> Double {
        let total = area
        guard total > 0 else { return 0 }
        let clipped = Self.clip(
            corners,
            to: LayoutRect(
                x: 0, y: 0, width: Double(canvasSize.width), height: Double(canvasSize.height)))
        return min(1, Self.area(of: clipped) / total)
    }

    static func area(of polygon: [LayoutPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            sum += current.x * next.y - next.x * current.y
        }
        return abs(sum) / 2
    }

    /// Sutherland–Hodgman clip of a convex polygon against an axis-aligned rectangle.
    static func clip(_ polygon: [LayoutPoint], to rect: LayoutRect) -> [LayoutPoint] {
        typealias Edge = (inside: (LayoutPoint) -> Bool, cross: (LayoutPoint, LayoutPoint) -> LayoutPoint)
        func crossX(_ edge: Double) -> (LayoutPoint, LayoutPoint) -> LayoutPoint {
            { a, b in
                let t = (edge - a.x) / (b.x - a.x)
                return LayoutPoint(x: edge, y: a.y + (b.y - a.y) * t)
            }
        }
        func crossY(_ edge: Double) -> (LayoutPoint, LayoutPoint) -> LayoutPoint {
            { a, b in
                let t = (edge - a.y) / (b.y - a.y)
                return LayoutPoint(x: a.x + (b.x - a.x) * t, y: edge)
            }
        }
        let maxX = rect.x + rect.width
        let maxY = rect.y + rect.height
        let edges: [Edge] = [
            ({ $0.x >= rect.x }, crossX(rect.x)), ({ $0.x <= maxX }, crossX(maxX)),
            ({ $0.y >= rect.y }, crossY(rect.y)), ({ $0.y <= maxY }, crossY(maxY)),
        ]
        var output = polygon
        for edge in edges {
            let input = output
            output = []
            guard let last = input.last else { break }
            var previous = last
            for point in input {
                switch (edge.inside(point), edge.inside(previous)) {
                case (true, true): output.append(point)
                case (true, false): output += [edge.cross(previous, point), point]
                case (false, true): output.append(edge.cross(previous, point))
                case (false, false): break
                }
                previous = point
            }
        }
        return output
    }
}
