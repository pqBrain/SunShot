public import CoreGraphics
public import SunshotCore

extension Renderer {
    /// S8: the backdrop with its effects (including an overlay above content) at `size` pixels, for inspector
    /// thumbnails. Same drawing as `render`, without content.
    public static func renderBackdrop(
        _ settings: BackdropSettings, size: PixelSize, media: [String: MediaAsset] = [:]
    ) throws -> CGImage {
        guard let context = makeContext(width: size.width, height: size.height) else {
            throw RenderError.contextCreationFailed
        }
        context.translateBy(x: 0, y: CGFloat(size.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        EffectsRenderer.drawBackdrop(settings, size: size, media: media, grid: nil, in: context)
        EffectsRenderer.drawAboveContent(settings.effects, size: size, in: context)
        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }
}
