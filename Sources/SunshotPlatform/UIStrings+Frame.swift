public import SunshotCore

/// S5 copy: Frame and Colors & Fonts sections.
extension UIStrings {
    public static let frameSection = "Frame"
    public static let colorsSection = "Colors & Fonts"
    public static let frameTitle = "Title"
    public static let frameTitlePlaceholder = "Window title"
    public static let uiScaleLabel = "UI scale"
    public static let chromeLabel = "Chrome"
    public static let textFontLabel = "Text"
    public static let codeFontLabel = "Code"
    public static let systemFont = "System"
    public static let systemMonoFont = "System Mono"
    public static let recommendedFonts = "Recommended"
    public static let installedFonts = "Installed"
    public static let fontUnavailable = "Font unavailable"
    public static let resetFonts = "Reset Fonts"
    public static let editTitleHint = "Double-click the title bar to edit the title"

    public static func frameName(_ kind: FrameKind) -> String {
        switch kind {
        case .none: "None"
        case .macWindow: "Mac window"
        case .browserWindow: "Browser window"
        case .card: "Card"
        case .stack: "Stack"
        case .stack2: "Stack 2"
        case .thickBorder: "Thick border"
        case .winWindow: "Windows window"
        }
    }

    /// VoiceOver label of a frame tile: "Frame: Mac window, selected".
    public static func frameOption(_ kind: FrameKind, selected: Bool) -> String {
        "Frame: \(frameName(kind))" + (selected ? ", selected" : "")
    }

    public static func uiScale(_ percent: Double) -> String { "UI scale, \(Int(percent.rounded())) percent" }

    public static func tokenName(_ token: ColorToken) -> String {
        switch token {
        case .foreground: "Foreground"
        case .background: "Background"
        case .secondary: "Secondary"
        case .primary: "Primary"
        }
    }

    /// Colour well label; its accessibility value is the hex string.
    public static func tokenWell(_ token: ColorToken) -> String { "\(tokenName(token)) color" }

    public static func appearanceName(_ appearance: ChromeAppearance) -> String {
        switch appearance {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Auto"
        }
    }

    public static func fontPicker(_ role: FontRole) -> String { role == .text ? "Text font" : "Code font" }
}
