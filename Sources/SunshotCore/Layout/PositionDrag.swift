import Foundation

/// Modifier keys that change a position drag.
public struct DragModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ⌥: free movement (no axis lock).
    public static let option = DragModifiers(rawValue: 1)
    /// ⌘: no snapping.
    public static let command = DragModifiers(rawValue: 2)
}

public enum DragAxis: Hashable, Sendable {
    case horizontal, vertical
}

/// Guide lines shown while dragging, in normalised canvas units.
public enum PositionGuide: Hashable, Sendable {
    /// The drag is locked to this axis; the line runs through the drag's start along it.
    case axisLock(DragAxis, through: Double)
    /// Snapped to the canvas centre line (vertical line at x = centre / horizontal line at y = centre).
    case centerX, centerY
    /// Snapped flush to a canvas edge.
    case leftEdge, rightEdge, topEdge, bottomEdge
}

/// Result of one drag update.
public struct PositionDragResult: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let guides: [PositionGuide]
}

/// Pure position-drag maths: axis lock, centre / edge snapping and clamping.
///
/// Distances are in the drag surface's pixels (the mini canvas in the Position popover), so the 8 px snap and
/// 6 px lock thresholds feel the same at any canvas size. The lock engages once the pointer has moved
/// `lockThreshold` px, and only when that movement is within `lockCone` degrees of an axis — a clearly diagonal
/// drag stays free. Once decided, the lock holds for the rest of the drag. ⌥ frees, ⌘ disables snapping.
public struct PositionDrag: Sendable {
    public static let snapThreshold: Double = 8
    public static let lockThreshold: Double = 6
    public static let lockCone: Double = 10
    /// Keyboard nudges (normalised units); ⇧ for the large step.
    public static let keyboardStep: Double = 0.01
    public static let largeKeyboardStep: Double = 0.05

    public let startX: Double
    public let startY: Double
    public let surfaceWidth: Double
    public let surfaceHeight: Double
    /// Half of the transformed content's bounding box, in canvas-width / canvas-height units (for edge snaps).
    public let halfExtentX: Double
    public let halfExtentY: Double
    public private(set) var lockedAxis: DragAxis?
    private var lockDecided = false

    public init(
        startX: Double, startY: Double, surfaceWidth: Double, surfaceHeight: Double, halfExtentX: Double = 0,
        halfExtentY: Double = 0
    ) {
        self.startX = ContentTransform.clampPosition(startX)
        self.startY = ContentTransform.clampPosition(startY)
        self.surfaceWidth = surfaceWidth.isFinite && surfaceWidth > 0 ? surfaceWidth : 1
        self.surfaceHeight = surfaceHeight.isFinite && surfaceHeight > 0 ? surfaceHeight : 1
        self.halfExtentX = halfExtentX.isFinite ? max(halfExtentX, 0) : 0
        self.halfExtentY = halfExtentY.isFinite ? max(halfExtentY, 0) : 0
    }

    /// The position for a pointer `translation` (surface px) from where the drag started.
    public mutating func update(
        translationX dx: Double, translationY dy: Double, modifiers: DragModifiers = []
    )
        -> PositionDragResult
    {
        let dx = dx.isFinite ? dx : 0
        let dy = dy.isFinite ? dy : 0
        if !lockDecided, hypot(dx, dy) >= Self.lockThreshold {
            lockDecided = true
            let angle = atan2(abs(dy), abs(dx)) * 180 / .pi
            if angle <= Self.lockCone {
                lockedAxis = .horizontal
            } else if angle >= 90 - Self.lockCone {
                lockedAxis = .vertical
            }
        }
        var x = startX + dx / surfaceWidth
        var y = startY + dy / surfaceHeight
        var guides: [PositionGuide] = []
        if !modifiers.contains(.option), let axis = lockedAxis {
            switch axis {
            case .horizontal: y = startY
            case .vertical: x = startX
            }
            guides.append(.axisLock(axis, through: axis == .horizontal ? startY : startX))
        }
        if !modifiers.contains(.command) {
            if lockedAxis != .vertical || modifiers.contains(.option) {
                let snapped = Self.snap(
                    x, half: halfExtentX, size: surfaceWidth, guides: (.centerX, .leftEdge, .rightEdge))
                x = snapped.value
                guides += snapped.guide.map { [$0] } ?? []
            }
            if lockedAxis != .horizontal || modifiers.contains(.option) {
                let snapped = Self.snap(
                    y, half: halfExtentY, size: surfaceHeight, guides: (.centerY, .topEdge, .bottomEdge))
                y = snapped.value
                guides += snapped.guide.map { [$0] } ?? []
            }
        }
        return PositionDragResult(
            x: ContentTransform.clampPosition(x), y: ContentTransform.clampPosition(y), guides: guides)
    }

    /// Snaps one axis: the centre line wins over the edges.
    static func snap(
        _ value: Double, half: Double, size: Double,
        guides: (center: PositionGuide, low: PositionGuide, high: PositionGuide)
    ) -> (value: Double, guide: PositionGuide?) {
        let threshold = snapThreshold / size
        if abs(value) <= threshold { return (0, guides.center) }
        // Content's low edge sits at 0.5 + value − half (canvas units from the low canvas edge).
        let lowFlush = half - 0.5
        if half > 0, abs(value - lowFlush) <= threshold { return (lowFlush, guides.low) }
        let highFlush = 0.5 - half
        if half > 0, abs(value - highFlush) <= threshold { return (highFlush, guides.high) }
        return (value, nil)
    }

    /// Keyboard nudge of a position value.
    public static func nudged(_ value: Double, by direction: Double, large: Bool) -> Double {
        ContentTransform.clampPosition(value + direction * (large ? largeKeyboardStep : keyboardStep))
    }
}

/// The Tilt tab's pad: the handle's offset from the centre (−1…1 each way, y down) maps to tilt.
/// The pad's edge is ±`edgeTilt`°; the sliders reach the full ±60°.
public enum TiltPad {
    public static let edgeTilt: Double = 30

    /// Right → positive `tiltY` (right side leans away); up → positive `tiltX` (top leans away).
    public static func tilt(handleX: Double, handleY: Double) -> (tiltX: Double, tiltY: Double) {
        let unitX = handleX.isFinite ? min(max(handleX, -1), 1) : 0
        let unitY = handleY.isFinite ? min(max(handleY, -1), 1) : 0
        return (ContentTransform.clampTilt(-unitY * edgeTilt + 0), ContentTransform.clampTilt(unitX * edgeTilt))
    }

    /// Where the handle sits for a transform (clamped to the pad).
    public static func handle(for transform: ContentTransform) -> (x: Double, y: Double) {
        (min(max(transform.tiltY / edgeTilt, -1), 1), min(max(-transform.tiltX / edgeTilt, -1), 1) + 0)
    }
}
