/// Every product default in one place. Tests reference these instead of literals.
public enum SunshotDefaults {
    /// Space around the content on every side, in canvas pixels.
    public static let padding: Double = 64
    /// Default backdrop colour, #EDEDF2.
    public static let backdropColor = RGBAColor(red: 237 / 255, green: 237 / 255, blue: 242 / 255)
    /// Largest padding a document accepts.
    public static let maxPadding: Double = 2000
    /// Corner style and radius (px at 1×) of new documents.
    public static let cornerStyle = CornerStyle.smooth
    public static let cornerRadius: Double = 24
    /// Shadow of new documents: a soft shadow falling slightly downward (light from above).
    public static let shadowStyle = ShadowStyle.spread
    public static let shadowIntensity = ShadowIntensity.medium
    public static let shadowOffset = UnitOffset(x: 0, y: 0.35)
    /// Largest canvas or export side in pixels (custom sizes and exports beyond this are refused).
    public static let maxCanvasSide = 16384
    /// New documents export PNG at 2×.
    public static let exportFormat = ExportFormat.png
    public static let exportScale = ExportScale.x2
    /// Lossy quality for JPEG and HEIC (0…1).
    public static let lossyQuality: Double = 0.9
    /// Export file name template and the `{TEMPLATE}` value until the template gallery exists (S12).
    public static let filenameTemplate = "{TEMPLATE}_{SCALE}_sunshot_{DATE}"
    public static let templateName = "screenshot"
    /// The live preview renders at most this many pixels on its long edge (exports are unaffected).
    public static let previewMaxSide = 6144
    /// How many undo steps are kept.
    public static let undoLimit = 100
    /// Gradient offered when the backdrop type is first switched to Gradient ("Sunrise Drift" in the presets).
    public static let gradient = GradientSpec(
        kind: .linear, angle: 135,
        stops: [
            GradientStop(position: 0, color: RGBAColor(rgb: 0xFFB36B)),
            GradientStop(position: 0.5, color: RGBAColor(rgb: 0xFF6F91)),
            GradientStop(position: 1, color: RGBAColor(rgb: 0x7B6CF6)),
        ])
    /// Wallpaper offered when the backdrop type is first switched to Image ("Lagoon" in the wallpaper set).
    public static let wallpaper = Wallpaper(
        id: "lagoon", name: "Lagoon", seed: 2611,
        base: GradientSpec(
            kind: .linear, angle: 160,
            stops: [
                GradientStop(position: 0, color: RGBAColor(rgb: 0x0F2A4A)),
                GradientStop(position: 1, color: RGBAColor(rgb: 0x1B5E7A)),
            ]),
        palette: [
            RGBAColor(rgb: 0x2EC4B6), RGBAColor(rgb: 0x6DD3F7), RGBAColor(rgb: 0x9B8CFF), RGBAColor(rgb: 0xFF9F6E),
        ],
        fieldCount: 6)
    /// S5: new documents have no frame, chrome at 100 % and chrome following the Background token.
    public static let frameKind = FrameKind.none
    public static let frameUIScale: Double = 100
    public static let chromeAppearance = ChromeAppearance.auto
    /// Colour tokens of new documents.
    public static let foregroundColor = RGBAColor(rgb: 0x1D1D1F)
    public static let backgroundColor = RGBAColor(rgb: 0xFFFFFF)
    public static let secondaryColor = RGBAColor(rgb: 0x6E6E73)
    public static let primaryColor = RGBAColor(rgb: 0x0A84FF)
    /// Fonts by PostScript name; empty = the system font (text) and the system monospaced font (code).
    public static let textFont = ""
    public static let codeFont = ""
}
