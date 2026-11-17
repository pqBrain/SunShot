import Foundation

/// A Sunshot code theme: background, text and one colour per token kind. Themes are data (`catalog`).
public struct CodeTheme: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isDark: Bool
    public let background: RGBAColor
    public let foreground: RGBAColor
    public let lineNumber: RGBAColor
    /// Band behind highlighted lines.
    public let highlight: RGBAColor
    public let title: RGBAColor
    /// Colour per token kind; `plain` (and any kind missing here) uses `foreground`.
    public let tokens: [CodeTokenKind: RGBAColor]

    public func color(for kind: CodeTokenKind) -> RGBAColor { tokens[kind] ?? foreground }

    public static let defaultID = "daybreak"

    /// The theme with `id`, or the default theme for an unknown id.
    public static func theme(id: String) -> CodeTheme {
        catalog.first { $0.id == id } ?? daybreak
    }

    /// Light themes first (Sunshot defaults to light), then dark.
    public static let catalog: [CodeTheme] = [daybreak, porcelain, midnight, ember]

    /// `base` = background, text, line numbers, highlight band, title (0xRRGGBB).
    private static func make(
        id: String, name: String, isDark: Bool, base: [UInt32], tokens: [CodeTokenKind: UInt32]
    ) -> CodeTheme {
        let colors = base.map { RGBAColor(rgb: $0) }
        return CodeTheme(
            id: id, name: name, isDark: isDark, background: colors[0], foreground: colors[1], lineNumber: colors[2],
            highlight: colors[3], title: colors[4], tokens: tokens.mapValues { RGBAColor(rgb: $0) })
    }

    /// Warm paper white.
    static let daybreak = make(
        id: "daybreak", name: "Daybreak", isDark: false,
        base: [0xFFFBF4, 0x2D2B36, 0x958F84, 0xF7E7C6, 0x6B6559],
        tokens: [
            .keyword: 0xC2410C, .type: 0x0F766E, .string: 0x15803D, .number: 0xB45309, .comment: 0x7D776C,
            .function: 0x1D4ED8, .property: 0x7C3AED, .tag: 0xBE123C, .attribute: 0xA16207, .variable: 0x0E7490,
            .punctuation: 0x6B6559,
        ])

    /// Cool blue-grey white.
    static let porcelain = make(
        id: "porcelain", name: "Porcelain", isDark: false,
        base: [0xF7F9FC, 0x1F2933, 0x8A96A3, 0xDCE8F7, 0x52606D],
        tokens: [
            .keyword: 0x7C3AED, .type: 0x0369A1, .string: 0x047857, .number: 0xC2410C, .comment: 0x6B7785,
            .function: 0x2563EB, .property: 0x9D174D, .tag: 0xBE185D, .attribute: 0xA16207, .variable: 0x0F766E,
            .punctuation: 0x52606D,
        ])

    /// Deep navy.
    static let midnight = make(
        id: "midnight", name: "Midnight", isDark: true,
        base: [0x141A2B, 0xE4E8F2, 0x5E6A85, 0x25304A, 0x9AA4BA],
        tokens: [
            .keyword: 0xFF8FB1, .type: 0x7DD3FC, .string: 0xA5E3A0, .number: 0xFFB86B, .comment: 0x7A86A3,
            .function: 0x8AB4FF, .property: 0xC4A7FF, .tag: 0xFF8FB1, .attribute: 0xFFD479, .variable: 0x6EE7D8,
            .punctuation: 0xA3ADC2,
        ])

    /// Warm charcoal.
    static let ember = make(
        id: "ember", name: "Ember", isDark: true,
        base: [0x1F1A17, 0xF1E7DC, 0x6F625A, 0x3A2E27, 0xB3A497],
        tokens: [
            .keyword: 0xFF9E64, .type: 0xF6C177, .string: 0xB8D98A, .number: 0xF7A1C4, .comment: 0x8F8075,
            .function: 0x7FC8F8, .property: 0xE8B4FF, .tag: 0xFF8A80, .attribute: 0xF6C177, .variable: 0x8EE3C8,
            .punctuation: 0xBBAEA2,
        ])
}

extension CodeTheme {
    /// WCAG 2 contrast ratio between two opaque colours (1…21).
    public static func contrast(_ first: RGBAColor, _ second: RGBAColor) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: RGBAColor) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}
