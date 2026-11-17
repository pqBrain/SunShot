/// S7: the left sidebar's picker (Layouts, Templates, Themes), the slimmer toolbar's Export menu and the
/// auto-backdrop setting.
extension UIStrings {
    public static let sidebarPickerAccessibility = "Show layouts, templates or themes"
    public static let themesTitle = "Themes"
    public static let themesEmpty = "No saved themes yet. Style the image, then save it here to reuse it."
    public static let saveCurrentTheme = "Save current style as theme"
    public static let templatesShowAll = "Show all templates…"
    public static let exportMenuAccessibility = "More export choices"
    public static let exportOptionsMenu = "Export Options…"
    public static let autoBackdropSetting = "Style the backdrop from the first image"

    /// "Theme: Ocean, applied" / "Theme: Ocean".
    public static func themeRow(_ name: String, applied: Bool) -> String {
        applied ? "Theme: \(name), applied" : "Theme: \(name)"
    }
}

/// S7: what the left sidebar shows. One picker instead of a sidebar, a toolbar gallery and an inspector menu.
public enum SidebarPane: String, CaseIterable, Identifiable, Sendable {
    case layouts, templates, themes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layouts: UIStrings.layoutsTitle
        case .templates: UIStrings.templatesTitle
        case .themes: UIStrings.themesTitle
        }
    }
}
