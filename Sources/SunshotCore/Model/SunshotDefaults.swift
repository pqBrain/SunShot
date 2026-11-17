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
}
