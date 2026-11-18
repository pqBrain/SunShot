/// S7: the left sidebar's picker (Layouts, Templates; S17 dropped Themes for the one default style), the slimmer
/// toolbar's Export menu and the auto-backdrop setting.
extension UIStrings {
    public static let sidebarPickerAccessibility = "Show layouts or templates"
    public static let templatesShowAll = "Show all templates…"
    public static let exportMenuAccessibility = "More export choices"
    public static let exportOptionsMenu = "Export Options…"
    public static let autoBackdropSetting = "Style the backdrop from the first image"
}

/// S7: what the left sidebar shows. One picker instead of a sidebar, a toolbar gallery and an inspector menu.
/// S17: no Themes pane; Set as Default is the one saved style.
public enum SidebarPane: String, CaseIterable, Identifiable, Sendable {
    case layouts, templates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layouts: UIStrings.layoutsTitle
        case .templates: UIStrings.templatesTitle
        }
    }
}
