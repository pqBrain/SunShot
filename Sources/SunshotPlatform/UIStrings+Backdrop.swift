public import SunshotCore

/// S3: Backdrop section copy and accessibility labels.
extension UIStrings {
    public static let backdropSection = "Backdrop"
    public static let backdropType = "Backdrop type"
    public static let hexField = "HEX"
    public static let hexFieldAccessibility = "Backdrop colour, HEX"
    public static let customColor = "Custom colour"
    public static let opacity = "Opacity"
    public static let gradientPresets = "Presets"
    public static let gradientStops = "Stops"
    public static let gradientAngle = "Angle"
    public static let gradientAngleAccessibility = "Gradient angle, degrees"
    public static let addStop = "Add Stop"
    public static let deleteStop = "Delete Stop"
    public static let stopColor = "Stop colour"
    public static let stopBarHint = "Click the bar to add a stop. Drag or use arrow keys to move one."
    public static let wallpapers = "Wallpapers"
    public static let chooseBackdropImage = "Choose Image…"
    public static let backdropDropHint = "Drop an image to use as the backdrop"
    public static let noneHint = "Transparent. The checkerboard shows only here, never in exports."
    public static let backdropImageFailed = "Can't use this image as a backdrop"

    public static func backdropKindName(_ kind: BackdropKind) -> String {
        switch kind {
        case .none: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .image: "Image"
        }
    }

    public static func gradientKindName(_ kind: GradientKind) -> String {
        switch kind {
        case .linear: "Linear"
        case .radial: "Radial"
        }
    }

    /// "Mist, #EDEDF2, selected" (the name is omitted when there is none).
    public static func swatch(name: String?, hex: String, selected: Bool) -> String {
        [name, hex, selected ? "selected" : nil].compactMap(\.self).joined(separator: ", ")
    }

    public static func gradientPreset(_ name: String, selected: Bool = false) -> String {
        "Gradient preset \(name)" + (selected ? ", selected" : "")
    }

    public static func wallpaper(_ name: String, selected: Bool = false) -> String {
        "Wallpaper \(name)" + (selected ? ", selected" : "")
    }

    /// "Gradient stop 2 of 3, #FF6F91, position 50 percent".
    public static func gradientStop(index: Int, count: Int, stop: GradientStop) -> String {
        "Gradient stop \(index + 1) of \(count), \(stop.color.hexString), position "
            + "\(Int((stop.position * 100).rounded())) percent"
    }

    public static func angle(_ degrees: Double) -> String { "\(Int(degrees.rounded()))°" }

    public static func backdropImageName(_ fileName: String?) -> String { fileName ?? "Image" }
}
