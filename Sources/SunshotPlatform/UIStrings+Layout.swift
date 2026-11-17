/// S6: position, tilt and layout copy and accessibility labels.
extension UIStrings {
    public static let positionButton = "Position"
    public static let positionButtonAccessibility = "Position, zoom, rotation and tilt"
    public static let positionTab = "Position"
    public static let tiltTab = "Tilt"
    public static let zoomLabel = "Zoom"
    public static let rotationLabel = "Rotation"
    public static let tiltXLabel = "Tilt X"
    public static let tiltYLabel = "Tilt Y"
    public static let resetPosition = "Reset position"
    public static let layoutsTitle = "Layouts"
    public static let layoutsEmpty = "Add an image to try layouts."
    public static let positionHint = "Drag to move. ⌥ moves freely, ⌘ turns off snapping."
    public static let tiltHint = "Drag toward an edge to lean the image in 3D."

    /// "Content position, x 0.00 y 0.00".
    public static func contentPosition(x: Double, y: Double) -> String {
        "Content position, x \(fixed(x)) y \(fixed(y))"
    }

    /// "Zoom, 100 percent".
    public static func zoom(_ percent: Double) -> String { "Zoom, \(Int(percent.rounded())) percent" }

    /// "Rotation, 0 degrees".
    public static func rotation(_ degrees: Double) -> String { "Rotation, \(Int(degrees.rounded())) degrees" }

    /// "Tilt, x 0 degrees, y 0 degrees".
    public static func tilt(x: Double, y: Double) -> String {
        "Tilt, x \(Int(x.rounded())) degrees, y \(Int(y.rounded())) degrees"
    }

    /// "Layout: Centered, selected" / "Layout: Tabletop".
    public static func layout(_ name: String, selected: Bool) -> String {
        selected ? "Layout: \(name), selected" : "Layout: \(name)"
    }

    /// Two decimals; "-0.00" is shown as "0.00".
    static func fixed(_ value: Double) -> String {
        let hundredths = value.isFinite ? Int((value * 100).rounded()) : 0
        let sign = hundredths < 0 ? "-" : ""
        let magnitude = abs(hundredths)
        let fraction = magnitude % 100
        return "\(sign)\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}
