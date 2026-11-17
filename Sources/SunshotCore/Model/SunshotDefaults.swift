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
}
