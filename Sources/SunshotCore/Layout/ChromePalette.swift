import Foundation

extension RGBAColor {
    /// WCAG relative luminance (0 black … 1 white), ignoring alpha.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colours (1…21).
    public static func contrast(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Double {
        let (a, b) = (lhs.relativeLuminance, rhs.relativeLuminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Straight interpolation towards `other` (0 = self, 1 = other).
    public func mixed(with other: RGBAColor, amount: Double) -> RGBAColor {
        let t = min(max(amount.isFinite ? amount : 0, 0), 1)
        return RGBAColor(
            red: red + (other.red - red) * t, green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }

    public func withAlpha(_ value: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: value)
    }
}

/// The colours window chrome is drawn with, resolved from the tokens and the chrome appearance.
public struct ChromePalette: Hashable, Sendable {
    /// Auto chrome keeps the user's Foreground / Secondary token unless it is this unreadable on the bar; then it
    /// switches to whichever built-in text colour reads better.
    public static let minimumTokenContrast: Double = 2
    /// Auto picks dark chrome below this Background luminance.
    public static let darkLuminanceThreshold: Double = 0.5

    public let isDark: Bool
    public let bar: RGBAColor
    public let title: RGBAColor
    public let glyph: RGBAColor
    public let field: RGBAColor
    public let separator: RGBAColor
    /// Fill behind the content inside a window (shows through transparent content).
    public let body: RGBAColor
    /// Accent used for small details (the browser's secure-site glyph).
    public let accent: RGBAColor

    public static let light = ChromePalette(
        isDark: false, bar: RGBAColor(rgb: 0xF4F4F6), title: RGBAColor(rgb: 0x1D1D1F), glyph: RGBAColor(rgb: 0x6E6E73),
        field: RGBAColor(rgb: 0xE4E4E9), separator: RGBAColor(rgb: 0x000000, alpha: 0.1),
        body: RGBAColor(rgb: 0xFFFFFF), accent: SunshotDefaults.primaryColor)

    public static let dark = ChromePalette(
        isDark: true, bar: RGBAColor(rgb: 0x2B2B30), title: RGBAColor(rgb: 0xF2F2F7), glyph: RGBAColor(rgb: 0xA1A1A8),
        field: RGBAColor(rgb: 0x3C3C42), separator: RGBAColor(rgb: 0xFFFFFF, alpha: 0.12),
        body: RGBAColor(rgb: 0x1C1C1F), accent: SunshotDefaults.primaryColor)

    public init(
        isDark: Bool, bar: RGBAColor, title: RGBAColor, glyph: RGBAColor, field: RGBAColor, separator: RGBAColor,
        body: RGBAColor, accent: RGBAColor
    ) {
        self.isDark = isDark
        self.bar = bar
        self.title = title
        self.glyph = glyph
        self.field = field
        self.separator = separator
        self.body = body
        self.accent = accent
    }

    /// Whether `appearance` resolves to dark chrome for these tokens.
    public static func isDark(_ tokens: DesignTokens) -> Bool {
        switch tokens.chromeAppearance {
        case .light: false
        case .dark: true
        case .auto: tokens.colors.background.relativeLuminance < darkLuminanceThreshold
        }
    }

    /// Light and dark force the built-in palettes; auto draws the bar in the Background token and the title in
    /// the Foreground token (falling back to a readable built-in colour, see `minimumTokenContrast`).
    public static func resolve(_ tokens: DesignTokens) -> ChromePalette {
        switch tokens.chromeAppearance {
        case .light: return light.accented(tokens.colors.primary)
        case .dark: return dark.accented(tokens.colors.primary)
        case .auto: break
        }
        let colors = tokens.colors
        let base = isDark(tokens) ? dark : light
        let bar = colors.background.withAlpha(1)
        let title = readable(colors.foreground, on: bar)
        let glyph = readable(colors.secondary, on: bar)
        return ChromePalette(
            isDark: base.isDark, bar: bar, title: title, glyph: glyph, field: bar.mixed(with: title, amount: 0.08),
            separator: title.withAlpha(0.12), body: bar, accent: colors.primary)
    }

    private func accented(_ color: RGBAColor) -> ChromePalette {
        ChromePalette(
            isDark: isDark, bar: bar, title: title, glyph: glyph, field: field, separator: separator, body: body,
            accent: color)
    }

    /// `token` when it reads on `bar`, else the built-in title colour with the better contrast.
    static func readable(_ token: RGBAColor, on bar: RGBAColor) -> RGBAColor {
        let opaque = token.withAlpha(1)
        if RGBAColor.contrast(opaque, bar) >= minimumTokenContrast { return opaque }
        let candidates = [light.title, dark.title]
        return candidates.max { RGBAColor.contrast($0, bar) < RGBAColor.contrast($1, bar) } ?? light.title
    }
}
