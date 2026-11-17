/// Every product default in one place. Tests reference these instead of literals.
public enum SunshotDefaults {
    /// Space around the content on every side, in canvas pixels.
    public static let padding: Double = 64
    /// Default backdrop colour, #EDEDF2.
    public static let backdropColor = RGBAColor(red: 237 / 255, green: 237 / 255, blue: 242 / 255)
    /// Largest padding a document accepts.
    public static let maxPadding: Double = 2000
    /// How many undo steps are kept.
    public static let undoLimit = 100
}
