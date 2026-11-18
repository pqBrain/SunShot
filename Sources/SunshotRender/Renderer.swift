public import CoreGraphics
public import SunshotCore

public enum RenderError: Error, Equatable {
    case contextCreationFailed
    case imageCreationFailed
    case noContent
}

/// The single render path shared by on-screen preview and export (guarantees preview/export parity).
public enum Renderer {
    /// Drops the renderer's cached preview backdrops (studio closed, memory pressure). The next preview render
    /// draws its backdrop again and re-fills the cache.
    public static func purgeCaches() {
        BackdropCache.shared.removeAll()
    }

    /// Preview and export both call this. Returns nil for an empty document.
    ///
    /// `showsTransparencyGrid` is set by the preview only: it draws `grid` behind a backdrop that isn't fully
    /// opaque. Everything else in the pipeline is identical, so exports and copies never contain the grid.
    public static func render(
        document: EditorDocument, scale: Double = 1, showsTransparencyGrid: Bool = false,
        grid: TransparencyGrid = .standard
    ) throws -> CGImage? {
        if let snippet = document.snippet {
            return try render(
                project: document.project, snippet: snippet, media: document.media, scale: scale,
                grid: showsTransparencyGrid ? grid : nil)
        }
        // S10: the crop is applied here, so the original image (and its saved bytes) stay intact.
        guard let (image, project) = croppedContent(of: document) else { return nil }
        return try render(
            project: project, content: image, media: document.media, scale: scale,
            grid: showsTransparencyGrid ? grid : nil, slots: document.slotImages)
    }

    /// Renders `project` with `content` at `scale` (1 = canvas points map to pixels).
    /// `layoutSize` lays out a downsampled proxy as if it were the full-size image (S14 strip thumbnails).
    /// `contentSize` is the content's size at 1× when the image is drawn at a higher density (code snippets).
    /// Both nil means the image's pixel size. `slots` are the S15 slot images (index → image).
    public static func render(
        project: Project, content: CGImage, contentSize: PixelSize? = nil, media: [String: MediaAsset] = [:],
        scale: Double = 1, grid: TransparencyGrid? = nil, layoutSize: PixelSize? = nil, slots: [Int: CGImage] = [:]
    ) throws -> CGImage {
        let contentSize = layoutSize ?? contentSize ?? PixelSize(width: content.width, height: content.height)
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

        BackdropCache.shared.drawBackdrop(
            project.backdropSettings, size: layout.canvasSize, media: media, grid: grid, in: context)
        let frameBox = FrameGeometry.layoutBox(for: project.frame, contentSize: contentSize)
        let collage = CollageLayout(
            project: project, boxWidth: frameBox.width + frameBox.insets.horizontal,
            boxHeight: frameBox.height + frameBox.insets.vertical)
        // S16: on a flat, single screenshot the annotations are drawn on top of everything, unclipped, so they can
        // reach out over the backdrop; elsewhere they stay on the content inside its silhouette.
        let freeAnnotations = drawsAnnotationsOnCanvas(project: project, collage: collage)
        var silhouetteProject = project
        if freeAnnotations { silhouetteProject.annotations.items.removeAll { $0.kind != .redact } }
        drawContent(
            content, slots: slots, collage: collage, layout: layout, project: silhouetteProject, scale: safeScale,
            context: context)
        EffectsRenderer.drawAboveContent(project.backdropSettings.effects, size: layout.canvasSize, in: context)
        if freeAnnotations { drawCanvasAnnotations(project.annotations, layout: layout, in: context) }

        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        return image
    }

    /// Whether annotations are drawn in canvas space (over the backdrop too): not through a moved, rotated or tilted
    /// content transform, a device mockup or a screenshot layout, which keep them on their screenshot.
    static func drawsAnnotationsOnCanvas(project: Project, collage: CollageLayout?) -> Bool {
        project.placement.transform.isIdentity && project.frame.device == nil && collage == nil
            && !project.annotations.isEmpty
    }

    /// The annotations in content pixels, placed where the content sits on the canvas and not clipped to it.
    private static func drawCanvasAnnotations(_ layer: AnnotationLayer, layout: CanvasLayout, in context: CGContext) {
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        context.saveGState()
        context.translateBy(x: layout.contentRect.x, y: layout.contentRect.y)
        context.scaleBy(x: style, y: style)
        AnnotationRenderer.draw(layer, in: context)
        context.restoreGState()
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
        _ image: CGImage, slots: [Int: CGImage], collage: CollageLayout?, layout: CanvasLayout, project: Project,
        scale: Double, context: CGContext
    ) {
        let rect = layout.frameRect
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        guard rect.width > 0, rect.height > 0 else { return }
        // Work in unscaled content units: the radius and shadow keep their 1× meaning.
        let target = CGRect(x: 0, y: 0, width: rect.width / style, height: rect.height / style)
        // S6: the content transform wraps the whole silhouette — S5 frame chrome, content and S9 annotations —
        // so a framed window moves, rotates and tilts as one object around the frame box's centre.
        let silhouette = CanvasLayout(
            canvasSize: layout.canvasSize, contentRect: layout.frameRect, styleScale: layout.styleScale)
        ContentTransformRenderer.draw(
            transform: project.placement.transform, layout: silhouette, shadow: ShadowMetrics.of(project.shadow),
            scale: scale, bounds: target, in: context
        ) { context in
            FrameRenderer.draw(
                image, project: project, in: target, slots: slots, collage: collage, context: context)
        }
    }
}

extension RGBAColor {
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
