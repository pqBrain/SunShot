public import AppKit
import SunshotCore
public import SunshotRender

/// UI colours. Semantic system colours so Light/Dark work automatically; contrast is unit-tested.
public enum SunshotPalette {
    public static let primaryText = NSColor.labelColor
    /// System `secondaryLabelColor` is ~4:1 on white (below WCAG AA), so Sunshot uses its own greys.
    public static let secondaryText = NSColor(name: "SunshotSecondaryText") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.66, green: 0.66, blue: 0.68, alpha: 1)
            : NSColor(srgbRed: 0.40, green: 0.40, blue: 0.43, alpha: 1)
    }
    /// Area behind the canvas.
    public static let workspaceBackground = NSColor.windowBackgroundColor
    /// Fill of the empty-state drop zone.
    public static let dropZoneFill = NSColor.controlBackgroundColor
    public static let dropZoneHighlight = NSColor.controlAccentColor
    /// Outlines of custom controls (light-source pad, crosshair). WCAG non-text contrast ≥ 3:1.
    public static let controlStroke = NSColor(name: "SunshotControlStroke") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1)
            : NSColor(srgbRed: 0.45, green: 0.45, blue: 0.49, alpha: 1)
    }
    /// Resting colour of the glass inspector panel, used as the contrast reference (glass adapts its own tint
    /// to what is behind it; this is the typical settled value per appearance).
    public static let inspectorSurface = NSColor(name: "SunshotInspectorSurface") { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1)
            : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)
    }

    /// Checkerboard behind transparent backdrops in the preview: two neutral greys per appearance.
    public static func transparencyGrid(dark: Bool) -> TransparencyGrid {
        dark
            ? TransparencyGrid(light: RGBAColor(rgb: 0x3A3A3F), dark: RGBAColor(rgb: 0x2A2A2E))
            : TransparencyGrid(light: RGBAColor(rgb: 0xFFFFFF), dark: RGBAColor(rgb: 0xDCDCE1))
    }

    /// Ring around the selected swatch / preset (system accent, so it follows the user's choice).
    public static let selectionRing = NSColor.controlAccentColor

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
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
