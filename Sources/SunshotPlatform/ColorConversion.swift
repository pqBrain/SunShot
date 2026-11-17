public import AppKit
public import SunshotCore

/// Bridges Sunshot's sRGB colours and the system colour panel / pickers.
extension RGBAColor {
    /// The colour in sRGB; nil for pattern or catalogue colours that have no sRGB equivalent.
    public init?(nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent))
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
