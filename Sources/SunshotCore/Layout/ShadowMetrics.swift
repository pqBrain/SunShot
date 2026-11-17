/// Concrete shadow numbers in canvas pixels at 1× (multiply by export scale).
public struct ShadowMetrics: Hashable, Sendable {
    public let blur: Double
    /// Shadow displacement in canvas pixels (x right, y down).
    public let offsetX: Double
    public let offsetY: Double
    /// Peak opacity of the shadow colour (black).
    public let opacity: Double

    public static let none = ShadowMetrics(blur: 0, offsetX: 0, offsetY: 0, opacity: 0)

    /// Hug shadows never reach further than this from the content edge.
    public static let hugMaxExtent: Double = 12

    public static func of(_ shadow: Shadow) -> ShadowMetrics {
        let blur: Double
        let maxOffset: Double
        let opacity: Double
        switch (shadow.style, shadow.intensity) {
        case (.none, _): return .none
        case (.spread, .low): (blur, maxOffset, opacity) = (20, 20, 0.16)
        case (.spread, .medium): (blur, maxOffset, opacity) = (30, 20, 0.26)
        case (.spread, .high): (blur, maxOffset, opacity) = (40, 20, 0.40)
        case (.hug, .low): (blur, maxOffset, opacity) = (6, 4, 0.22)
        case (.hug, .medium): (blur, maxOffset, opacity) = (7, 4, 0.34)
        case (.hug, .high): (blur, maxOffset, opacity) = (8, 4, 0.50)
        }
        return ShadowMetrics(
            blur: blur, offsetX: shadow.offset.x * maxOffset, offsetY: shadow.offset.y * maxOffset, opacity: opacity)
    }

    /// Furthest the shadow can reach beyond the content edge.
    public var extent: Double { blur + max(abs(offsetX), abs(offsetY)) }

    public func scaled(by scale: Double) -> ShadowMetrics {
        ShadowMetrics(blur: blur * scale, offsetX: offsetX * scale, offsetY: offsetY * scale, opacity: opacity)
    }
}

/// Corner geometry shared by the renderer and tests.
public enum CornerGeometry {
    /// Continuous corners start this many radii away from the corner (circular corners start at 1×).
    public static let smoothExtent: Double = 1.28

    /// The radius actually drawn: sharp ignores it; otherwise limited to half the shorter side.
    public static func effectiveRadius(_ border: Border, width: Double, height: Double) -> Double {
        guard border.style != .sharp else { return 0 }
        return max(0, min(border.radius, min(width, height) / 2))
    }
}
