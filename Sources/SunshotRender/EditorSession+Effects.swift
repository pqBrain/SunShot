import CoreGraphics
public import SunshotCore

/// S8: backdrop effects and auto backgrounds. Each edit is one named undo step; edits that change nothing record
/// nothing; slider drags use `beginGesture` / `endGesture` like the other controls.
extension EditorSession {
    public static let blurActionName = "Change Backdrop Blur"
    public static let noiseActionName = "Change Backdrop Noise"
    public static let saturationActionName = "Change Backdrop Saturation"
    public static let backdropOpacityActionName = "Change Backdrop Opacity"
    public static let resetAdjustmentsActionName = "Reset Adjustments"
    public static let patternActionName = "Change Pattern"
    public static let patternIntensityActionName = "Change Pattern Intensity"
    public static let patternThicknessActionName = "Change Pattern Thickness"
    public static let patternColorActionName = "Change Pattern Colour"
    public static let resetPatternActionName = "Reset Pattern"
    public static let vignetteActionName = "Change Vignette"
    public static let vignetteSpreadActionName = "Change Vignette Spread"
    public static let vignetteIntensityActionName = "Change Vignette Intensity"
    public static let resetVignetteActionName = "Reset Vignette"
    public static let overlayActionName = "Change Overlay"
    public static let overlayOpacityActionName = "Change Overlay Opacity"
    public static let overlayPositionActionName = "Change Overlay Position"
    public static let resetOverlayActionName = "Reset Overlay"
    public static let autoBackgroundActionName = "Apply Auto Background"
    public static let shuffleActionName = "Shuffle Auto Backgrounds"

    public var backdropEffects: BackdropEffects { project.backdropSettings.effects }

    // MARK: Adjustments

    public mutating func setBackdropBlur(_ value: Double) {
        editEffects(Self.blurActionName) { $0.adjustments.blur = value }
    }

    public mutating func setBackdropNoise(_ value: Double) {
        editEffects(Self.noiseActionName) { $0.adjustments.noise = value }
    }

    public mutating func setBackdropSaturation(_ value: Double) {
        editEffects(Self.saturationActionName) { $0.adjustments.saturation = value }
    }

    public mutating func setBackdropOpacity(_ value: Double) {
        editEffects(Self.backdropOpacityActionName) { $0.adjustments.opacity = value }
    }

    public mutating func resetAdjustments() {
        editEffects(Self.resetAdjustmentsActionName) { $0.adjustments = BackdropAdjustments() }
    }

    // MARK: Pattern

    public mutating func setPatternKind(_ kind: PatternKind) {
        editEffects(Self.patternActionName) { $0.pattern.kind = kind }
    }

    public mutating func setPatternIntensity(_ value: Double) {
        editEffects(Self.patternIntensityActionName) { $0.pattern.intensity = value }
    }

    public mutating func setPatternThickness(_ value: Double) {
        editEffects(Self.patternThicknessActionName) { $0.pattern.thickness = value }
    }

    public mutating func setPatternColor(_ color: RGBAColor) {
        editEffects(Self.patternColorActionName) { $0.pattern.color = color }
    }

    public mutating func resetPattern() {
        editEffects(Self.resetPatternActionName) { $0.pattern = BackdropPattern() }
    }

    // MARK: Vignette

    public mutating func setVignetteStyle(_ style: VignetteStyle) {
        editEffects(Self.vignetteActionName) { $0.vignette.style = style }
    }

    public mutating func setVignetteSpread(_ value: Double) {
        editEffects(Self.vignetteSpreadActionName) { $0.vignette.spread = value }
    }

    public mutating func setVignetteIntensity(_ value: Double) {
        editEffects(Self.vignetteIntensityActionName) { $0.vignette.intensity = value }
    }

    public mutating func resetVignette() {
        editEffects(Self.resetVignetteActionName) { $0.vignette = Vignette() }
    }

    // MARK: Overlay

    public mutating func setOverlayKind(_ kind: OverlayKind) {
        editEffects(Self.overlayActionName) { $0.overlay.kind = kind }
    }

    public mutating func setOverlayOpacity(_ value: Double) {
        editEffects(Self.overlayOpacityActionName) { $0.overlay.opacity = value }
    }

    public mutating func setOverlayPosition(_ position: OverlayPosition) {
        editEffects(Self.overlayPositionActionName) { $0.overlay.position = position }
    }

    public mutating func resetOverlay() {
        editEffects(Self.resetOverlayActionName) { $0.overlay = OverlayTexture() }
    }

    // MARK: Auto backgrounds

    /// Six prominent colours of the content (empty without content or with fully transparent content).
    public var autoPalette: [RGBAColor] {
        guard let content = document.content else { return [] }
        return ContentPalette.extract(from: content.image)
    }

    /// The five generated backgrounds for the current palette and shuffle value.
    public var autoBackgrounds: [Wallpaper] {
        AutoBackground.suggestions(palette: autoPalette, shuffle: project.backdropSettings.autoShuffle)
    }

    /// Uses a generated background (selects the Image type).
    public mutating func applyAutoBackground(_ wallpaper: Wallpaper) {
        history.applyIfChanged(Self.autoBackgroundActionName) { Self.select(wallpaper, in: &$0) }
    }

    /// Moves to the next arrangement and applies its first background. No-op without a palette.
    public mutating func shuffleAutoBackgrounds() {
        let palette = autoPalette
        let next = AutoBackground.nextShuffle(after: project.backdropSettings.autoShuffle)
        guard let first = AutoBackground.suggestions(palette: palette, shuffle: next).first else { return }
        history.applyIfChanged(Self.shuffleActionName) { document in
            document.project.backdropSettings.autoShuffle = next
            Self.select(first, in: &document)
        }
    }

    private static func select(_ wallpaper: Wallpaper, in document: inout EditorDocument) {
        document.project.backdrop = .image(.wallpaper(wallpaper))
        // The user image (if any) is no longer referenced; undo keeps it in the earlier state.
        let keep = document.project.backdropSettings.mediaReference?.id
        document.media = document.media.filter { $0.key == keep }
    }

    private mutating func editEffects(_ name: String, _ change: (inout BackdropEffects) -> Void) {
        editProject(name) { change(&$0.backdropSettings.effects) }
    }
}

/// Samples the content at a small size and extracts its palette.
enum ContentPalette {
    /// Long edge of the sample in pixels (plenty for six colours, cheap in debug builds).
    static let sampleSide = 64

    static func extract(from image: CGImage, count: Int = PaletteExtractor.defaultCount) -> [RGBAColor] {
        let scale = min(1, Double(sampleSide) / Double(max(image.width, image.height, 1)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = Renderer.makeContext(width: width, height: height), let data = context.data else {
            return []
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let base = data.assumingMemoryBound(to: UInt8.self)
        var rgba: [UInt8] = []
        rgba.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * rowBytes + x * 4
                let alpha = Int(pixel[3])
                // Un-premultiply: the extractor works on straight colours.
                for channel in 0..<3 {
                    rgba.append(alpha == 0 ? 0 : UInt8(min(255, (Int(pixel[channel]) * 255 + alpha / 2) / alpha)))
                }
                rgba.append(UInt8(alpha))
            }
        }
        return PaletteExtractor.extract(rgba: rgba, count: count)
    }
}
