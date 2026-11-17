import Foundation

/// What a point on the canvas belongs to: the (projected) screenshot with its frame chrome, or the backdrop.
public enum CanvasRegion: Hashable, Sendable {
    case content
    case backdrop
}

/// S6: hit-testing the canvas for direct manipulation in the main preview.
public enum CanvasHitTest {
    /// The region under `point` (canvas pixels). The content quad is the frame box (content + frame chrome) carried
    /// through the same projection the renderer uses, so a tilted or rotated screenshot is hit where it is drawn.
    public static func region(at point: LayoutPoint, layout: CanvasLayout, transform: ContentTransform) -> CanvasRegion
    {
        contains(quad(layout: layout, transform: transform), point) ? .content : .backdrop
    }

    /// The projected frame box on the canvas: top-left, top-right, bottom-right, bottom-left.
    public static func quad(layout: CanvasLayout, transform: ContentTransform) -> [LayoutPoint] {
        let projection = ContentProjection(
            contentRect: layout.contentRect, canvasSize: layout.canvasSize, transform: transform)
        let content = layout.contentRect
        let frame = layout.frameRect
        // Frame box corners in the content's local coordinates (origin at the content's top-left).
        let left = frame.x - content.x
        let top = frame.y - content.y
        let right = left + frame.width
        let bottom = top + frame.height
        return [
            LayoutPoint(x: left, y: top), LayoutPoint(x: right, y: top),
            LayoutPoint(x: right, y: bottom), LayoutPoint(x: left, y: bottom),
        ].map(projection.project)
    }

    /// Mean of the polygon's vertices (the centre of a projected rectangle's quad, near enough for directions).
    public static func centre(of polygon: [LayoutPoint]) -> LayoutPoint {
        guard !polygon.isEmpty else { return LayoutPoint(x: 0, y: 0) }
        let count = Double(polygon.count)
        return LayoutPoint(
            x: polygon.reduce(0) { $0 + $1.x } / count, y: polygon.reduce(0) { $0 + $1.y } / count)
    }

    /// Point-in-convex-polygon: inside when the point is on the same side of every edge.
    static func contains(_ polygon: [LayoutPoint], _ point: LayoutPoint) -> Bool {
        guard polygon.count >= 3, point.x.isFinite, point.y.isFinite else { return false }
        var sign = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if cross == 0 { continue }
            if sign == 0 {
                sign = cross
            } else if (cross > 0) != (sign > 0) {
                return false
            }
        }
        return sign != 0
    }
}

/// S6: pinch on the canvas. Zoom follows the magnification from where the pinch started.
public struct CanvasPinch: Hashable, Sendable {
    public let startZoom: Double

    public init(startZoom: Double) { self.startZoom = ContentTransform.clampZoom(startZoom) }

    /// Whole percent, clamped to the zoom range. Non-finite or non-positive magnification keeps the start zoom.
    public func zoom(magnification: Double) -> Double {
        guard magnification.isFinite, magnification > 0 else { return startZoom }
        return ContentTransform.clampZoom(startZoom * magnification)
    }
}

/// S6: two-finger twist on the canvas. Rotation follows the twist and snaps to multiples of 45°.
public struct CanvasTwist: Hashable, Sendable {
    public static let snapStep: Double = 45
    public static let snapThreshold: Double = 4

    public let startRotation: Double

    public init(startRotation: Double) { self.startRotation = ContentTransform.normaliseRotation(startRotation) }

    /// Whole degrees, normalised into −180…180; within `snapThreshold` of a multiple of 45° it snaps there.
    public func rotation(angle: Double, snaps: Bool = true) -> Double {
        let angle = angle.isFinite ? angle : 0
        let raw = (startRotation + angle).rounded()
        guard snaps else { return ContentTransform.normaliseRotation(raw) }
        let nearest = (raw / Self.snapStep).rounded() * Self.snapStep
        let value = abs(raw - nearest) <= Self.snapThreshold ? nearest : raw
        return ContentTransform.normaliseRotation(value)
    }
}

/// S6: the preview renders at the size it is displayed (sharp when it fills the editor), never above
/// `SunshotDefaults.previewMaxSide`.
public enum PreviewSizing {
    /// Displayed longest side is quantised to this many pixels so a window resize doesn't re-render every point.
    public static let quantum: Double = 128

    /// The render scale for a canvas of `canvas` px shown in a box whose longest side fits `displayPixels`
    /// device pixels. Without a display size it is 1 (one canvas pixel per preview pixel), capped by the max side.
    public static func scale(canvas: PixelSize, displayPixels: (width: Double, height: Double)?) -> Double {
        let width = Double(max(canvas.width, 1))
        let height = Double(max(canvas.height, 1))
        let cap = Double(SunshotDefaults.previewMaxSide) / max(width, height)
        guard let display = displayPixels, display.width.isFinite, display.height.isFinite,
            display.width > 0, display.height > 0
        else { return min(1, cap) }
        let fit = min(display.width / width, display.height / height)
        let quantised = max((fit * max(width, height) / quantum).rounded(.up), 1) * quantum / max(width, height)
        return min(max(quantised, 1), cap)
    }
}
