import Foundation

/// The eight grips on the capture selection: four edges and four corners.
public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// The grip under `point` (display points): within `tolerance` of an edge, corners first. Nil elsewhere,
    /// including the middle of the selection.
    public static func hit(
        rect: LayoutRect, point: (x: Double, y: Double), tolerance: Double = 10
    )
        -> SelectionHandle?
    {
        guard point.x >= rect.x - tolerance, point.x <= rect.x + rect.width + tolerance,
            point.y >= rect.y - tolerance, point.y <= rect.y + rect.height + tolerance
        else { return nil }
        let left = abs(point.x - rect.x) <= tolerance
        let right = abs(point.x - (rect.x + rect.width)) <= tolerance
        let top = abs(point.y - rect.y) <= tolerance
        let bottom = abs(point.y - (rect.y + rect.height)) <= tolerance
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    /// `rect` with this grip dragged to `point`, kept inside the display and never smaller than `minimum` on a side
    /// (an edge stops at the opposite one instead of flipping over it).
    public func resized(
        _ rect: LayoutRect, to point: (x: Double, y: Double), displayWidth: Double, displayHeight: Double,
        minimum: Double = AreaSelection.minimumSide
    ) -> LayoutRect {
        var minX = rect.x
        var maxX = rect.x + rect.width
        var minY = rect.y
        var maxY = rect.y + rect.height
        if movesLeft { minX = min(max(point.x, 0), maxX - minimum) }
        if movesRight { maxX = max(min(point.x, displayWidth), minX + minimum) }
        if movesTop { minY = min(max(point.y, 0), maxY - minimum) }
        if movesBottom { maxY = max(min(point.y, displayHeight), minY + minimum) }
        return LayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
