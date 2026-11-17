public import SunshotCore

/// User-facing copy and accessibility labels for S1, kept here so tests can pin them.
public enum UIStrings {
    public static let dropTitle = "Drop an image here"
    public static let chooseImage = "Choose Image…"
    public static let pasteHint = "or press ⌘V to paste"
    public static let openImage = "Open Image…"
    public static let exportImage = "Export Image…"
    public static let copyPNG = "Copy PNG"
    public static let paste = "Paste Image"
    public static let clearContent = "Clear Content"
    public static let importing = "Opening image…"

    public static let chooseImageAccessibility = "Choose Image, ⌘O"
    public static let copyAccessibility = "Copy PNG, ⌘C"
    public static let clearAccessibility = "Clear content"

    // MARK: S2 inspector
    public static let inspector = "Inspector"
    public static let toggleInspector = "Show or hide inspector, ⌥⌘E"
    public static let borderSection = "Border"
    public static let shadowSection = "Shadow"
    public static let reset = "Reset"
    public static let inspectorEmpty = "Add an image to style it."

    public static func resetSection(_ section: String) -> String { "Reset \(section)" }

    public static func cornerStyleName(_ style: CornerStyle) -> String {
        switch style {
        case .sharp: "Sharp"
        case .smooth: "Smooth"
        case .round: "Round"
        }
    }

    public static func shadowStyleName(_ style: ShadowStyle) -> String {
        switch style {
        case .none: "None"
        case .spread: "Spread"
        case .hug: "Hug"
        }
    }

    public static func intensityName(_ intensity: ShadowIntensity) -> String {
        switch intensity {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func cornerStyle(_ style: CornerStyle) -> String { "Corner style: \(style.rawValue)" }
    public static func cornerRadius(_ radius: Double) -> String { "Corner radius, \(Int(radius.rounded())) pixels" }
    public static func shadowStyle(_ style: ShadowStyle) -> String { "Shadow style: \(style.rawValue)" }
    public static func shadowIntensity(_ value: ShadowIntensity) -> String { "Shadow intensity: \(value.rawValue)" }

    /// VoiceOver label for the light-source handle.
    public static func lightDirection(_ position: UnitOffset) -> String {
        "Light direction, x \(format(position.x)), y \(format(position.y))"
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == 0 ? "0" : String(rounded)
    }
}
