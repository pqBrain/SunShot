import Foundation

/// An sRGB colour with straight (non-premultiplied) alpha. Components are clamped to `0...1`.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` (the leading `#` is optional). Returns `nil` for anything else.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        func channel(_ offset: UInt64) -> Double { Double((value >> (offset + shift)) & 0xFF) / 255 }
        self.init(
            red: channel(16),
            green: channel(8),
            blue: channel(0),
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }

    /// Uppercase `#RRGGBB`, or `#RRGGBBAA` when not fully opaque.
    public var hexString: String {
        func byte(_ component: Double) -> String { String(format: "%02X", Int((component * 255).rounded())) }
        let rgb = "#" + byte(red) + byte(green) + byte(blue)
        return alpha >= 1 ? rgb : rgb + byte(alpha)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
