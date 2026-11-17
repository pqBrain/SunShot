/// Ratio presets offered by the crop dialog. `free` has no constraint; `original` keeps the image's own ratio.
public enum CropAspect: String, CaseIterable, Codable, Hashable, Sendable {
    case free, original, square, landscape4x3, portrait3x4, landscape3x2, portrait2x3, wide16x9, tall9x16

    /// Width ÷ height, or nil for free cropping.
    public func ratio(for imageSize: PixelSize) -> Double? {
        switch self {
        case .free: nil
        case .original: imageSize.aspectRatio
        case .square: 1
        case .landscape4x3: 4.0 / 3.0
        case .portrait3x4: 3.0 / 4.0
        case .landscape3x2: 3.0 / 2.0
        case .portrait2x3: 2.0 / 3.0
        case .wide16x9: 16.0 / 9.0
        case .tall9x16: 9.0 / 16.0
        }
    }
}

/// A handle of the crop rectangle, or its interior (`move`).
public enum CropHandle: Hashable, Sendable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    /// Which edges the handle moves: -1 = min edge, +1 = max edge, 0 = none.
    var horizontal: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .topRight, .right, .bottomRight: 1
        case .top, .bottom, .move: 0
        }
    }

    var vertical: Int {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .bottomLeft, .bottom, .bottomRight: 1
        case .left, .right, .move: 0
        }
    }

    var isCorner: Bool { horizontal != 0 && vertical != 0 }
}

/// Pure crop maths (S10), in content pixels with the image's top-left at the origin.
public enum CropGeometry {
    /// Smallest crop side, in content pixels (smaller images allow their own size).
    public static let minimumSide: Double = 16

    /// The largest rect of `ratio` that fits inside `rect`, centred on it (a ratio preset applied to the current
    /// crop). With no ratio, `rect` itself.
    public static func fit(ratio: Double?, inside rect: LayoutRect) -> LayoutRect {
        guard let ratio, ratio.isFinite, ratio > 0, rect.width > 0, rect.height > 0 else { return rect }
        var width = rect.width
        var height = width / ratio
        if height > rect.height {
            height = rect.height
            width = height * ratio
        }
        return LayoutRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// The rect after dragging `handle` by (`dx`, `dy`) content pixels from `start`. The result always stays
    /// inside the image, keeps at least `minimumSide` per side, never flips, and keeps `ratio` when one is set.
    public static func drag(
        _ handle: CropHandle, from start: LayoutRect, dx: Double, dy: Double, ratio: Double?, imageSize: PixelSize
    ) -> LayoutRect {
        let dx = dx.isFinite ? dx : 0
        let dy = dy.isFinite ? dy : 0
        let bounds = (width: Double(imageSize.width), height: Double(imageSize.height))
        let minSide = min(minimumSide, bounds.width, bounds.height)
        if handle == .move {
            let x = min(max(start.x + dx, 0), bounds.width - start.width)
            let y = min(max(start.y + dy, 0), bounds.height - start.height)
            return LayoutRect(x: max(0, x), y: max(0, y), width: start.width, height: start.height)
        }
        if let ratio, ratio.isFinite, ratio > 0 {
            return constrainedDrag(handle, from: start, dx: dx, dy: dy, ratio: ratio, bounds: bounds, minSide: minSide)
        }
        var minX = start.x
        var maxX = start.x + start.width
        var minY = start.y
        var maxY = start.y + start.height
        switch handle.horizontal {
        case -1: minX = min(max(minX + dx, 0), maxX - minSide)
        case 1: maxX = max(min(maxX + dx, bounds.width), minX + minSide)
        default: break
        }
        switch handle.vertical {
        case -1: minY = min(max(minY + dy, 0), maxY - minSide)
        case 1: maxY = max(min(maxY + dy, bounds.height), minY + minSide)
        default: break
        }
        return LayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Ratio-locked resize. Corners are anchored at the opposite corner; edges at the opposite edge and centred
    /// on the other axis.
    private static func constrainedDrag(
        _ handle: CropHandle, from start: LayoutRect, dx: Double, dy: Double, ratio: Double,
        bounds: (width: Double, height: Double), minSide: Double
    ) -> LayoutRect {
        let anchorX = handle.horizontal == -1 ? start.x + start.width : start.x
        let anchorY = handle.vertical == -1 ? start.y + start.height : start.y
        // The room available from the anchor in the handle's direction (centred axes use both sides).
        let roomX: Double =
            switch handle.horizontal {
            case -1: anchorX
            case 1: bounds.width - anchorX
            default: 2 * min(start.midX, bounds.width - start.midX)
            }
        let roomY: Double =
            switch handle.vertical {
            case -1: anchorY
            case 1: bounds.height - anchorY
            default: 2 * min(start.midY, bounds.height - start.midY)
            }
        var width = start.width + Double(handle.horizontal) * dx
        var height = start.height + Double(handle.vertical) * dy
        if handle.isCorner {
            if width / max(height, 0.0001) > ratio { height = width / ratio } else { width = height * ratio }
        } else if handle.horizontal != 0 {
            height = width / ratio
        } else {
            width = height * ratio
        }
        // Largest size that fits the room, smallest that keeps both sides ≥ minSide.
        let maxWidth = min(roomX, roomY * ratio)
        let minWidth = min(max(minSide, minSide * ratio), maxWidth)
        width = min(max(width, minWidth), maxWidth)
        height = width / ratio
        let x: Double =
            switch handle.horizontal {
            case -1: anchorX - width
            case 1: anchorX
            default: start.midX - width / 2
            }
        let y: Double =
            switch handle.vertical {
            case -1: anchorY - height
            case 1: anchorY
            default: start.midY - height / 2
            }
        return LayoutRect(x: x, y: y, width: width, height: height)
    }

    /// The handle under `point` (content pixels), corners first, then edges, then the interior; nil outside.
    /// `tolerance` is the grab distance in content pixels.
    public static func handle(at point: AnnotationPoint, in rect: LayoutRect, tolerance: Double) -> CropHandle? {
        let maxX = rect.x + rect.width
        let maxY = rect.y + rect.height
        let nearMinX = abs(point.x - rect.x) <= tolerance
        let nearMaxX = abs(point.x - maxX) <= tolerance
        let nearMinY = abs(point.y - rect.y) <= tolerance
        let nearMaxY = abs(point.y - maxY) <= tolerance
        let insideX = point.x >= rect.x - tolerance && point.x <= maxX + tolerance
        let insideY = point.y >= rect.y - tolerance && point.y <= maxY + tolerance
        guard insideX, insideY else { return nil }
        switch (nearMinX, nearMaxX, nearMinY, nearMaxY) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .move
        }
    }
}
