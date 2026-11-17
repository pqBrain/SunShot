import Foundation

/// S6: dragging the backdrop changes the padding. Moving the pointer away from the screenshot's centre grows it,
/// toward the centre shrinks it. Distances are view points; `pixelsPerPoint` converts them to canvas pixels as they
/// were when the drag started (the Auto canvas grows with the padding, so the live scale would feed back).
public struct PaddingDrag: Hashable, Sendable {
    public let startPadding: Double
    public let pixelsPerPoint: Double
    /// Unit vector from the screenshot's centre toward the press (0, 0 when pressed on the centre).
    public let directionX: Double
    public let directionY: Double

    public init(startPadding: Double, pixelsPerPoint: Double, pressX: Double, pressY: Double) {
        self.startPadding = startPadding.isFinite ? startPadding : SunshotDefaults.padding
        self.pixelsPerPoint = pixelsPerPoint.isFinite && pixelsPerPoint > 0 ? pixelsPerPoint : 1
        let length = hypot(pressX, pressY)
        if length.isFinite, length > 0 {
            directionX = pressX / length
            directionY = pressY / length
        } else {
            directionX = 0
            directionY = 0
        }
    }

    /// Whole pixels within 0…`SunshotDefaults.maxPadding`. A press on the centre follows the larger axis movement.
    public func padding(translationX dx: Double, translationY dy: Double) -> Double {
        let dx = dx.isFinite ? dx : 0
        let dy = dy.isFinite ? dy : 0
        let outward: Double
        if directionX == 0, directionY == 0 {
            outward = abs(dx) >= abs(dy) ? dx : dy
        } else {
            outward = dx * directionX + dy * directionY
        }
        let value = (startPadding + outward * pixelsPerPoint).rounded()
        return min(max(value, 0), SunshotDefaults.maxPadding)
    }
}

/// S6: ⇧-drag on the screenshot tilts it, like the Tilt pad: dragging right leans the right side away (`tiltY`),
/// dragging up leans the top away (`tiltX`). Crossing `pointsPerEdge` points reaches the pad's edge tilt.
public struct TiltDrag: Hashable, Sendable {
    public static let pointsPerEdge: Double = 200

    public let startTiltX: Double
    public let startTiltY: Double

    public init(start: ContentTransform) {
        startTiltX = start.tiltX
        startTiltY = start.tiltY
    }

    /// Whole degrees, clamped to the tilt range.
    public func tilt(translationX dx: Double, translationY dy: Double) -> (tiltX: Double, tiltY: Double) {
        let dx = dx.isFinite ? dx : 0
        let dy = dy.isFinite ? dy : 0
        let perPoint = TiltPad.edgeTilt / Self.pointsPerEdge
        return (
            ContentTransform.clampTilt((startTiltX - dy * perPoint).rounded()),
            ContentTransform.clampTilt((startTiltY + dx * perPoint).rounded())
        )
    }
}

/// S6: the corner-radius handle drawn inside the screenshot's top-left corner. It sits `radius` in from the corner
/// on both axes (at least `minimumInset` points so it stays grabbable); dragging it diagonally sets the radius.
public enum CornerRadiusHandle {
    public static let minimumInset: Double = 12

    /// Inset of the handle from the corner, in view points, for a radius in content pixels.
    public static func inset(radius: Double, pointsPerPixel: Double) -> Double {
        let scale = pointsPerPixel.isFinite && pointsPerPixel > 0 ? pointsPerPixel : 1
        let radius = radius.isFinite ? radius : 0
        return max(radius * scale, minimumInset)
    }

    /// The radius after dragging the handle by a translation (view points): the mean of both axes moves it.
    public static func radius(
        start: Double, translationX dx: Double, translationY dy: Double, pointsPerPixel: Double
    )
        -> Double
    {
        let scale = pointsPerPixel.isFinite && pointsPerPixel > 0 ? pointsPerPixel : 1
        let dx = dx.isFinite ? dx : 0
        let dy = dy.isFinite ? dy : 0
        return Border.clamp((start + (dx + dy) / 2 / scale).rounded())
    }
}
