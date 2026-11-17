public import CoreGraphics
public import SunshotCore

public enum RenderError: Error, Equatable {
    case contextCreationFailed
    case imageCreationFailed
    case noContent
}

/// The single render path shared by on-screen preview and export (guarantees preview/export parity).
public enum Renderer {
    /// Preview and export both call this. Returns nil for an empty document.
    ///
    /// `showsTransparencyGrid` is set by the preview only: it draws `grid` behind a backdrop that isn't fully
    /// opaque. Everything else in the pipeline is identical, so exports and copies never contain the grid.
    public static func render(
        document: EditorDocument, scale: Double = 1, showsTransparencyGrid: Bool = false,
        grid: TransparencyGrid = .standard
    ) throws -> CGImage? {
        guard let content = document.content else { return nil }
        return try render(
            project: document.project, content: content.image, media: document.media, scale: scale,
            grid: showsTransparencyGrid ? grid : nil)
    }

    /// Renders `project` with `content` at `scale` (1 = canvas points map to pixels).
    /// `layoutSize` lays out a downsampled proxy as if it were the full-size image (S14 strip thumbnails).
    public static func render(
        project: Project, content: CGImage, media: [String: MediaAsset] = [:], scale: Double = 1,
        grid: TransparencyGrid? = nil, layoutSize: PixelSize? = nil
    ) throws -> CGImage {
        let contentSize = layoutSize ?? PixelSize(width: content.width, height: content.height)
        let layout = CanvasLayout.compute(contentSize: contentSize, project: project)
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let pixelWidth = ExportPlan.scaled(layout.canvasSize.width, by: safeScale)
        let pixelHeight = ExportPlan.scaled(layout.canvasSize.height, by: safeScale)

        guard let context = makeContext(width: pixelWidth, height: pixelHeight) else {
            throw RenderError.contextCreationFailed
        }
        // Flip to a top-left origin so all layout maths matches Core's coordinate system.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(safeScale), y: -CGFloat(safeScale))
        context.interpolationQuality = .high

        EffectsRenderer.drawBackdrop(
            project.backdropSettings, size: layout.canvasSize, media: media, grid: grid, in: context)
        drawContent(content, layout: layout, project: project, scale: safeScale, context: context)
        EffectsRenderer.drawAboveContent(project.backdropSettings.effects, size: layout.canvasSize, in: context)

        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// The backdrop alone at `size` pixels (inspector thumbnails), through the same backdrop drawing as `render`.
    public static func renderBackdrop(
        _ backdrop: Backdrop, size: PixelSize, media: [String: MediaAsset] = [:]
    ) throws -> CGImage {
        guard let context = makeContext(width: size.width, height: size.height) else {
            throw RenderError.contextCreationFailed
        }
        context.translateBy(x: 0, y: CGFloat(size.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        BackdropRenderer.draw(backdrop, size: size, media: media, grid: nil, in: context)
        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    /// Draws the content clipped to its corner shape, with a shadow derived from the clipped content's alpha
    /// (so transparent cut-outs cast no shadow). On exact canvases the content, its corners and its shadow are
    /// scaled together by `layout.styleScale`, so the look is the same as on an Auto canvas, just resized.
    /// The frame (S5) is drawn with the content by `FrameRenderer`, inside the same shadow layer.
    private static func drawContent(
        _ image: CGImage, layout: CanvasLayout, project: Project, scale: Double, context: CGContext
    ) {
        let rect = layout.frameRect
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        guard rect.width > 0, rect.height > 0 else { return }
        // Work in unscaled content units: the radius and shadow keep their 1× meaning.
        let target = CGRect(x: 0, y: 0, width: rect.width / style, height: rect.height / style)
        let metrics = ShadowMetrics.of(project.shadow).scaled(by: scale * style)

        context.saveGState()
        context.translateBy(x: rect.x, y: rect.y)
        context.scaleBy(x: style, y: style)
        if metrics.opacity > 0 {
            // Shadow offsets are in device space (y up), unaffected by our flipped CTM: negate y to fall down.
            context.setShadow(
                offset: CGSize(width: metrics.offsetX, height: -metrics.offsetY), blur: metrics.blur,
                color: CGColor(gray: 0, alpha: metrics.opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        FrameRenderer.draw(image, project: project, in: target, context: context)
        if metrics.opacity > 0 { context.endTransparencyLayer() }
        context.restoreGState()
    }
}

extension RGBAColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
