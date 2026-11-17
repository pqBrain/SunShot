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
    public static func render(
        project: Project, content: CGImage, media: [String: MediaAsset] = [:], scale: Double = 1,
        grid: TransparencyGrid? = nil
    ) throws -> CGImage {
        let contentSize = PixelSize(width: content.width, height: content.height)
        let layout = CanvasLayout.compute(contentSize: contentSize, project: project)
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let pixelWidth = Int((Double(layout.canvasSize.width) * safeScale).rounded())
        let pixelHeight = Int((Double(layout.canvasSize.height) * safeScale).rounded())

        guard let context = makeContext(width: pixelWidth, height: pixelHeight) else {
            throw RenderError.contextCreationFailed
        }
        // Flip to a top-left origin so all layout maths matches Core's coordinate system.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(safeScale), y: -CGFloat(safeScale))
        context.interpolationQuality = .high

        BackdropRenderer.draw(project.backdrop, size: layout.canvasSize, media: media, grid: grid, in: context)
        drawContent(content, in: layout.contentRect, project: project, scale: safeScale, context: context)

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
    /// (so transparent cut-outs cast no shadow).
    private static func drawContent(
        _ image: CGImage, in rect: LayoutRect, project: Project, scale: Double, context: CGContext
    ) {
        let target = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        guard target.width > 0, target.height > 0 else { return }
        let shape = ContentShape.path(for: project.border, in: target)
        let metrics = ShadowMetrics.of(project.shadow).scaled(by: scale)

        context.saveGState()
        if metrics.opacity > 0 {
            // Shadow offsets are in device space (y up), unaffected by our flipped CTM: negate y to fall down.
            context.setShadow(
                offset: CGSize(width: metrics.offsetX, height: -metrics.offsetY), blur: metrics.blur,
                color: CGColor(gray: 0, alpha: metrics.opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.saveGState()
        context.addPath(shape)
        context.clip()
        // Images draw bottom-up; undo the flip locally so content is not mirrored.
        context.translateBy(x: 0, y: target.minY + target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: target)
        context.restoreGState()
        if metrics.opacity > 0 { context.endTransparencyLayer() }
        context.restoreGState()
    }
}

extension RGBAColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
