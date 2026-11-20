public import CoreGraphics
public import SunshotCore

/// Draws the "window silhouette" — frame chrome plus content — into a frame box. Called by `Renderer.render`
/// inside the content's shadow layer, so preview and export share it, and so later transforms (position, tilt)
/// can wrap the whole silhouette. With frame `none` it draws exactly what S2 drew: the clipped content.
public enum FrameRenderer {
    /// `box` is the frame box in the current (top-left origin) user space, in unscaled content pixels.
    /// `slots` are the S15 slot images (index → image); a slot without one shows `image`. `collage` is the
    /// screenshot layout laid out around the primary frame box (the box then holds the whole layout).
    public static func draw(
        _ image: CGImage, project: Project, in box: CGRect, slots: [Int: CGImage] = [:],
        collage: CollageLayout? = nil, context: CGContext
    ) {
        // S9: redaction replaces content pixels before anything is drawn, so originals never reach the output.
        let image = RedactionRenderer.apply(project.annotations, to: image)
        context.saveGState()
        context.translateBy(x: box.minX, y: box.minY)
        defer { context.restoreGState() }

        // S12: a device mockup replaces the frame chrome.
        if let device = DeviceLayout(frame: project.frame) {
            let local = CGRect(origin: .zero, size: box.size)
            DeviceRenderer.draw(
                image, slots: slots, layout: device, annotations: project.annotations, box: local, context: context)
            return
        }
        // S15: a screenshot layout draws the frame silhouette once per slot.
        if let collage {
            CollageRenderer.draw(
                image, slots: slots, layout: collage, project: project, box: box.size, context: context)
            return
        }
        drawSilhouette(image, project: project, size: box.size, annotations: project.annotations, context: context)
    }

    /// One frame silhouette (chrome + content + annotations) in a local box at the origin.
    static func drawSilhouette(
        _ image: CGImage, project: Project, size: CGSize, annotations: AnnotationLayer, context: CGContext
    ) {
        let geometry = FrameGeometry(frame: project.frame, boxWidth: size.width, boxHeight: size.height)
        switch project.frame.kind {
        case .none:
            drawClippedContent(image, border: project.border, geometry: geometry, context: context)
            drawAnnotations(annotations, in: geometry.content.cg, context: context)
        case .macWindow, .browserWindow, .winWindow:
            drawWindow(image, geometry: geometry, project: project, context: context)
            drawAnnotations(annotations, in: geometry.content.cg, context: context)
        case .card, .stack, .stack2, .stack3, .stack4:
            // Explicit dark chrome gives a dark card; light and auto keep the Background token.
            let fill =
                project.tokens.chromeAppearance == .dark ? ChromePalette.dark.body : project.tokens.colors.background
            drawCards(image, geometry: geometry, project: project, fill: fill, context)
            drawAnnotations(annotations, in: geometry.content.cg, context: context)
        case .thickBorder:
            drawCards(image, geometry: geometry, project: project, fill: project.tokens.colors.secondary, context)
            drawAnnotations(annotations, in: geometry.content.cg, context: context)
        }
    }

    /// The S2 look: content clipped to its corner shape.
    private static func drawClippedContent(
        _ image: CGImage, border: Border, geometry: FrameGeometry, context: CGContext
    ) {
        context.saveGState()
        context.addPath(ContentShape.path(for: border, in: geometry.window.cg))
        context.clip()
        drawImage(image, in: geometry.content.cg, context: context)
        context.restoreGState()
    }

    /// S9 annotations, in content pixels with the content's top-left at the origin, clipped to the content.
    private static func drawAnnotations(_ layer: AnnotationLayer, in content: CGRect, context: CGContext) {
        guard !layer.isEmpty else { return }
        context.saveGState()
        context.clip(to: content)
        context.translateBy(x: content.minX, y: content.minY)
        AnnotationRenderer.draw(layer, in: context)
        context.restoreGState()
    }

    /// Images draw bottom-up; undo the flip locally so content is not mirrored.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    // MARK: Windows

    private static func drawWindow(_ image: CGImage, geometry: FrameGeometry, project: Project, context: CGContext) {
        let palette = ChromePalette.resolve(project.tokens)
        let window = geometry.window.cg
        context.saveGState()
        context.addPath(ContentShape.path(for: project.border, in: window))
        context.clip()
        context.setFillColor(palette.body.cgColor)
        context.fill(window)
        if let bar = geometry.bar?.cg {
            context.setFillColor(palette.bar.cgColor)
            context.fill(bar)
            context.setFillColor(palette.separator.cgColor)
            context.fill(CGRect(x: bar.minX, y: bar.maxY - geometry.scale, width: bar.width, height: geometry.scale))
            FrameChrome.drawBar(
                geometry: geometry, palette: palette, fonts: project.tokens.fonts, title: project.frame.displayTitle,
                context: context)
        }
        drawImage(image, in: geometry.content.cg, context: context)
        context.restoreGState()
    }

    // MARK: Cards and thick border

    /// Card / stack: the content on a card of `fill`; thick border: the content in a ring of `fill`. Both are
    /// concentric — the outer radius is the S2 radius plus the padding — and the inner area behind transparent
    /// content shows the Background token, never the backdrop.
    private static func drawCards(
        _ image: CGImage, geometry: FrameGeometry, project: Project, fill: RGBAColor, _ context: CGContext
    ) {
        var outer = project.border
        outer.radius = project.border.radius + geometry.outerRadiusExtra
        for card in geometry.backCards {
            context.addPath(ContentShape.path(for: outer, in: card.rect.cg))
            context.setFillColor(fill.withAlpha(fill.alpha * card.opacity).cgColor)
            context.fillPath()
        }
        context.addPath(ContentShape.path(for: outer, in: geometry.window.cg))
        context.setFillColor(fill.cgColor)
        context.fillPath()

        let inner = ContentShape.path(for: project.border, in: geometry.content.cg)
        context.saveGState()
        context.addPath(inner)
        context.clip()
        if geometry.kind == .thickBorder {
            context.setFillColor(project.tokens.colors.background.cgColor)
            context.fill(geometry.content.cg)
        }
        drawImage(image, in: geometry.content.cg, context: context)
        context.restoreGState()
    }
}

extension LayoutRect {
    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
