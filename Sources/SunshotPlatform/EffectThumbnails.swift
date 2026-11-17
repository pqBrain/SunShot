public import CoreGraphics
public import SunshotCore
import SunshotRender

/// S8: thumbnails for the pattern and overlay pickers, drawn by the same renderer as the canvas on a sample
/// backdrop. Rendered once, then cached.
@MainActor
public final class EffectThumbnails {
    public static let shared = EffectThumbnails()

    /// The backdrop the overlay samples are drawn on (patterns use the default solid colour).
    static let sample = BackdropSettings(kind: .gradient)

    private var images: [String: CGImage] = [:]

    public init() {}

    public func pattern(_ kind: PatternKind) -> CGImage? {
        var settings = BackdropSettings()
        settings.effects.pattern = BackdropPattern(kind: kind, intensity: 0.5)
        return image(key: "pattern:\(kind.rawValue)", settings)
    }

    public func overlay(_ kind: OverlayKind) -> CGImage? {
        var settings = Self.sample
        settings.effects.overlay = OverlayTexture(kind: kind, opacity: 0.6)
        return image(key: "overlay:\(kind.rawValue)", settings)
    }

    private func image(key: String, _ settings: BackdropSettings) -> CGImage? {
        if let cached = images[key] { return cached }
        guard let image = try? Renderer.renderBackdrop(settings, size: BackdropLibrary.thumbnailSize) else {
            return nil
        }
        images[key] = image
        return image
    }
}
