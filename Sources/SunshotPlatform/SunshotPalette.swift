public import AppKit

/// UI colours. Semantic system colours so Light/Dark work automatically; contrast is unit-tested.
public enum SunshotPalette {
    public static let primaryText = NSColor.labelColor
    /// System `secondaryLabelColor` is ~4:1 on white (below WCAG AA), so Sunshot uses its own greys.
    public static let secondaryText = NSColor(name: "SunshotSecondaryText") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.66, green: 0.66, blue: 0.68, alpha: 1)
            : NSColor(srgbRed: 0.40, green: 0.40, blue: 0.43, alpha: 1)
    }
    /// Area behind the canvas.
    public static let workspaceBackground = NSColor.windowBackgroundColor
    /// Fill of the empty-state drop zone.
    public static let dropZoneFill = NSColor.controlBackgroundColor
    public static let dropZoneStroke = NSColor.separatorColor
    public static let dropZoneHighlight = NSColor.controlAccentColor
}

public enum Contrast {
    /// WCAG 2.x contrast ratio of `foreground` (composited over `background`) under `appearance`.
    public static func ratio(_ foreground: NSColor, on background: NSColor, appearance: NSAppearance) -> Double {
        var result = 1.0
        appearance.performAsCurrentDrawingAppearance {
            guard let bg = background.usingColorSpace(.sRGB), let fg = foreground.usingColorSpace(.sRGB) else { return }
            let alpha = fg.alphaComponent
            func blend(_ f: CGFloat, _ b: CGFloat) -> CGFloat { f * alpha + b * (1 - alpha) }
            let fgLum = luminance(
                blend(fg.redComponent, bg.redComponent), blend(fg.greenComponent, bg.greenComponent),
                blend(fg.blueComponent, bg.blueComponent))
            let bgLum = luminance(bg.redComponent, bg.greenComponent, bg.blueComponent)
            result = (max(fgLum, bgLum) + 0.05) / (min(fgLum, bgLum) + 0.05)
        }
        return result
    }

    private static func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Double {
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.040_45 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
