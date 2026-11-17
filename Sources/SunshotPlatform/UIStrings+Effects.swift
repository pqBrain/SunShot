public import SunshotCore

/// S8: Effects subsection and Auto backgrounds copy and accessibility labels.
extension UIStrings {
    public static let effects = "Effects"
    public static let overlayButton = "Overlay"
    public static let adjustButton = "Adjust"
    public static let patternButton = "Pattern"
    public static let vignetteButton = "Vignette"
    public static let effectBlur = "Blur"
    public static let effectNoise = "Noise"
    public static let effectSaturation = "Saturation"
    public static let effectOpacity = "Opacity"
    public static let effectIntensity = "Intensity"
    public static let effectThickness = "Thickness"
    public static let effectSpread = "Spread"
    public static let patternColor = "Pattern colour"
    public static let overlayPosition = "Overlay position"
    public static let adjustHint = "Applies to the backdrop only."
    public static let autoBackgrounds = "Auto"
    public static let autoPalette = "Palette from your image"
    public static let autoShuffle = "Shuffle"
    public static let autoShuffleAccessibility = "Shuffle auto backgrounds"

    public static func patternName(_ kind: PatternKind) -> String {
        switch kind {
        case .none: "None"
        case .circles: "Circles"
        case .waves: "Waves"
        case .dots: "Dots"
        case .rays: "Rays"
        case .grid: "Grid"
        case .stripes: "Stripes"
        case .noise: "Noise"
        }
    }

    public static func vignetteName(_ style: VignetteStyle) -> String {
        switch style {
        case .none: "None"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    public static func overlayName(_ kind: OverlayKind) -> String {
        switch kind {
        case .none: "None"
        case .blinds: "Blinds"
        case .window: "Window"
        case .leaves: "Leaves"
        case .lattice: "Lattice"
        case .ripples: "Ripples"
        case .dapple: "Dapple"
        }
    }

    public static func overlayPositionName(_ position: OverlayPosition) -> String {
        switch position {
        case .above: "Above content"
        case .below: "Below content"
        }
    }

    /// "12 px" / "40 %": the value shown next to a slider.
    public static func effectPixels(_ value: Double) -> String { "\(Int(value.rounded())) px" }
    public static func effectPercent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded())) %" }

    /// VoiceOver: "Blur, 12 pixels" / "Noise, 40 percent".
    public static func effectSliderAccessibility(_ title: String, pixels value: Double) -> String {
        "\(title), \(Int(value.rounded())) pixels"
    }

    public static func effectSliderAccessibility(_ title: String, percent fraction: Double) -> String {
        "\(title), \(Int((fraction * 100).rounded())) percent"
    }

    /// "Pattern, Dots" / "Overlay, Leaves, on" for the effect buttons.
    public static func effectButton(_ title: String, value: String, isOn: Bool) -> String {
        "\(title), \(value)" + (isOn ? ", on" : "")
    }

    public static func effectPickerItem(_ group: String, _ name: String, selected: Bool) -> String {
        "\(group), \(name)" + (selected ? ", selected" : "")
    }

    /// "Auto background 2 of 5, selected".
    public static func autoBackground(index: Int, count: Int, selected: Bool) -> String {
        "Auto background \(index + 1) of \(count)" + (selected ? ", selected" : "")
    }

    /// "Blur 12 px, Noise 40 %" (only the values that differ from the default), or "None".
    public static func adjustSummary(_ adjustments: BackdropAdjustments) -> String {
        let defaults = BackdropAdjustments()
        let parts = [
            adjustments.blur != defaults.blur ? "\(effectBlur) \(effectPixels(adjustments.blur))" : nil,
            adjustments.noise != defaults.noise ? "\(effectNoise) \(effectPercent(adjustments.noise))" : nil,
            adjustments.saturation != defaults.saturation
                ? "\(effectSaturation) \(effectPercent(adjustments.saturation))" : nil,
            adjustments.opacity != defaults.opacity ? "\(effectOpacity) \(effectPercent(adjustments.opacity))" : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    /// "Palette: #3060E0, #E04030, …".
    public static func paletteAccessibility(_ colors: [RGBAColor]) -> String {
        "Palette: " + colors.map(\.hexString).joined(separator: ", ")
    }
}
