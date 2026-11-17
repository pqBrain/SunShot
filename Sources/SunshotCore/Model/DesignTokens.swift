import Foundation

/// The four colour tokens that drive frame chrome (and later text and annotations).
public enum ColorToken: String, Codable, CaseIterable, Sendable {
    case foreground, background, secondary, primary
}

public struct ColorTokens: Codable, Hashable, Sendable {
    public var foreground: RGBAColor
    public var background: RGBAColor
    public var secondary: RGBAColor
    public var primary: RGBAColor

    public init(
        foreground: RGBAColor = SunshotDefaults.foregroundColor,
        background: RGBAColor = SunshotDefaults.backgroundColor,
        secondary: RGBAColor = SunshotDefaults.secondaryColor, primary: RGBAColor = SunshotDefaults.primaryColor
    ) {
        self.foreground = foreground
        self.background = background
        self.secondary = secondary
        self.primary = primary
    }

    private enum CodingKeys: String, CodingKey { case foreground, background, secondary, primary }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ColorTokens()
        self.init(
            foreground: try container.decodeIfPresent(RGBAColor.self, forKey: .foreground) ?? defaults.foreground,
            background: try container.decodeIfPresent(RGBAColor.self, forKey: .background) ?? defaults.background,
            secondary: try container.decodeIfPresent(RGBAColor.self, forKey: .secondary) ?? defaults.secondary,
            primary: try container.decodeIfPresent(RGBAColor.self, forKey: .primary) ?? defaults.primary)
    }

    public subscript(token: ColorToken) -> RGBAColor {
        get {
            switch token {
            case .foreground: foreground
            case .background: background
            case .secondary: secondary
            case .primary: primary
            }
        }
        set {
            switch token {
            case .foreground: foreground = newValue
            case .background: background = newValue
            case .secondary: secondary = newValue
            case .primary: primary = newValue
            }
        }
    }
}

/// Which font family to use, stored by PostScript name. An empty name means the system font.
public enum FontRole: String, Codable, CaseIterable, Sendable {
    case text, code
}

public struct FontTokens: Codable, Hashable, Sendable {
    public var text: String
    public var code: String

    public init(text: String = SunshotDefaults.textFont, code: String = SunshotDefaults.codeFont) {
        self.text = text
        self.code = code
    }

    private enum CodingKeys: String, CodingKey { case text, code }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try container.decodeIfPresent(String.self, forKey: .text) ?? SunshotDefaults.textFont,
            code: try container.decodeIfPresent(String.self, forKey: .code) ?? SunshotDefaults.codeFont)
    }

    public subscript(role: FontRole) -> String {
        get { role == .text ? text : code }
        set {
            if role == .text { text = newValue } else { code = newValue }
        }
    }
}

/// Light or dark chrome. `auto` follows the Background token's luminance (not the system appearance).
public enum ChromeAppearance: String, Codable, CaseIterable, Sendable {
    case light, dark, auto

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChromeAppearance(rawValue: raw) ?? SunshotDefaults.chromeAppearance
    }
}

/// Colours, fonts and chrome appearance of a document.
public struct DesignTokens: Codable, Hashable, Sendable {
    public var colors: ColorTokens
    public var fonts: FontTokens
    public var chromeAppearance: ChromeAppearance

    public init(
        colors: ColorTokens = ColorTokens(), fonts: FontTokens = FontTokens(),
        chromeAppearance: ChromeAppearance = SunshotDefaults.chromeAppearance
    ) {
        self.colors = colors
        self.fonts = fonts
        self.chromeAppearance = chromeAppearance
    }

    private enum CodingKeys: String, CodingKey { case colors, fonts, chromeAppearance }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            colors: try container.decodeIfPresent(ColorTokens.self, forKey: .colors) ?? ColorTokens(),
            fonts: try container.decodeIfPresent(FontTokens.self, forKey: .fonts) ?? FontTokens(),
            chromeAppearance: try container.decodeIfPresent(ChromeAppearance.self, forKey: .chromeAppearance)
                ?? SunshotDefaults.chromeAppearance)
    }
}
