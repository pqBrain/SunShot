public import CoreGraphics
public import SunshotCore

/// Outline of the content after corner rounding, in canvas coordinates (top-left origin).
public enum ContentShape {
    public static func path(for border: Border, in rect: CGRect) -> CGPath {
        let radius = CornerGeometry.effectiveRadius(border, width: rect.width, height: rect.height)
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        switch border.style {
        case .sharp:
            return CGPath(rect: rect, transform: nil)
        case .round:
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .smooth:
            return continuousPath(in: rect, radius: radius)
        }
    }

    /// Continuous corners: each corner is one cubic that starts further from the corner than a circular arc
    /// (up to `CornerGeometry.smoothExtent` × radius) and eases into the straight edge. When there's no room for
    /// the longer transition it gracefully becomes a circular corner (no inverted or overlapping corners).
    static func continuousPath(in rect: CGRect, radius: Double) -> CGPath {
        let half = min(rect.width, rect.height) / 2
        let extentFactor = max(1, min(CornerGeometry.smoothExtent, half / radius))
        let extent = radius * extentFactor
        // Control-point distance from the corner: 0.4477 r is a circular arc; smaller is squarer (continuous).
        let progress = (extentFactor - 1) / (CornerGeometry.smoothExtent - 1)
        let control = radius * (0.4477 + progress * (0.25 - 0.4477))

        let path = CGMutablePath()
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        path.move(to: CGPoint(x: minX + extent, y: minY))
        path.addLine(to: CGPoint(x: maxX - extent, y: minY))
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + extent), control1: CGPoint(x: maxX - control, y: minY),
            control2: CGPoint(x: maxX, y: minY + control))
        path.addLine(to: CGPoint(x: maxX, y: maxY - extent))
        path.addCurve(
            to: CGPoint(x: maxX - extent, y: maxY), control1: CGPoint(x: maxX, y: maxY - control),
            control2: CGPoint(x: maxX - control, y: maxY))
        path.addLine(to: CGPoint(x: minX + extent, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - extent), control1: CGPoint(x: minX + control, y: maxY),
            control2: CGPoint(x: minX, y: maxY - control))
        path.addLine(to: CGPoint(x: minX, y: minY + extent))
        path.addCurve(
            to: CGPoint(x: minX + extent, y: minY), control1: CGPoint(x: minX, y: minY + control),
            control2: CGPoint(x: minX + control, y: minY))
        path.closeSubpath()
        return path
    }
}
