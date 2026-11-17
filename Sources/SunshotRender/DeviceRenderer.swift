import CoreGraphics
import SunshotCore

/// Draws a device mockup (S12) — every device of the layout, back to front, with the content aspect-filled into
/// each screen — into a frame box. Called by `FrameRenderer` inside the shadow layer and the S6 transform, so
/// devices cast the document shadow, move and tilt as one object, and preview and export match.
enum DeviceRenderer {
    /// Opacity of the soft gloss across each screen (top-left to centre).
    static let glossOpacity: Double = 0.06
    /// Colour of a camera lens and of its ring.
    static let lensColor = RGBAColor(rgb: 0x16181C)

    /// `box` is local (origin 0, 0), in unscaled content units; `annotations` draw on the primary screen.
    /// `slots` (S15) give a device its own image by arrangement slot index; the others show `image`.
    static func draw(
        _ image: CGImage, slots: [Int: CGImage] = [:], layout: DeviceLayout, annotations: AnnotationLayer,
        box: CGRect, context: CGContext
    ) {
        let fitted = layout.fitted(toWidth: box.width)
        for (index, device) in fitted.devices.enumerated() {
            let shown = device.isPrimary ? image : slots[index] ?? image
            for part in device.parts {
                if part.role == .screen {
                    drawScreen(shown, part: part, finish: fitted.finish, context: context)
                    if device.isPrimary { drawAnnotations(annotations, image: image, screen: part.rect.cg, context) }
                } else {
                    drawPart(part, finish: fitted.finish, unit: device.unit, context: context)
                }
            }
        }
    }

    static func path(_ part: DevicePart) -> CGPath {
        let rect = part.rect.cg
        let radius = min(part.radius, min(rect.width, rect.height) / 2)
        guard radius > 0 else { return CGPath(rect: rect, transform: nil) }
        return ContentShape.continuousPath(in: rect, radius: radius)
    }

    private static func drawPart(_ part: DevicePart, finish: DeviceFinish, unit: Double, context: CGContext) {
        let shape = path(part)
        context.saveGState()
        defer { context.restoreGState() }
        switch part.role {
        case .shell:
            context.addPath(shape)
            context.clip()
            let rect = part.rect.cg
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [finish.highlight.cgColor, finish.shell.cgColor] as CFArray, locations: [0, 1])
            {
                context.drawLinearGradient(
                    gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.minX, y: rect.maxY),
                    options: [])
            } else {
                context.setFillColor(finish.shell.cgColor)
                context.fill(rect)
            }
            // A hairline edge inside the silhouette (clipped, so it never grows the outline).
            context.addPath(shape)
            context.setStrokeColor(finish.edge.cgColor)
            context.setLineWidth(max(0.5, 3 * unit))
            context.strokePath()
        case .edge, .detail, .bezel:
            let color = part.role == .edge ? finish.edge : part.role == .detail ? finish.detail : finish.bezel
            context.addPath(shape)
            context.setFillColor(color.cgColor)
            context.fillPath()
        case .lens:
            let rect = part.rect.cg
            context.setFillColor(lensColor.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(finish.detail.withAlpha(0.6).cgColor)
            context.setLineWidth(max(0.25, unit))
            context.strokeEllipse(in: rect.insetBy(dx: unit / 2, dy: unit / 2))
        case .screen:
            break
        }
    }

    /// Black glass, then the content aspect-filled (centre crop), then a faint gloss, all clipped to the screen.
    private static func drawScreen(_ image: CGImage, part: DevicePart, finish: DeviceFinish, context: CGContext) {
        let rect = part.rect.cg
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(path(part))
        context.clip()
        context.setFillColor(finish.bezel.cgColor)
        context.fill(rect)
        FrameRenderer.drawImage(image, in: aspectFill(image, in: rect), context: context)
        if let gloss = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [RGBAColor.white.withAlpha(glossOpacity).cgColor, RGBAColor.white.withAlpha(0).cgColor]
                as CFArray, locations: [0, 1])
        {
            context.drawLinearGradient(
                gloss, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.midY),
                options: [])
        }
    }

    /// Where the image goes so it covers `rect` with its aspect kept, centred.
    static func aspectFill(_ image: CGImage, in rect: CGRect) -> CGRect {
        let width = Double(image.width)
        let height = Double(image.height)
        guard width > 0, height > 0 else { return rect }
        let scale = max(rect.width / width, rect.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        return CGRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// S9 annotations sit on the content as drawn in the primary screen (content units; the screen crops them).
    private static func drawAnnotations(
        _ layer: AnnotationLayer, image: CGImage, screen: CGRect, _ context: CGContext
    ) {
        guard !layer.isEmpty else { return }
        let placed = aspectFill(image, in: screen)
        context.saveGState()
        context.clip(to: screen)
        context.translateBy(x: placed.minX, y: placed.minY)
        AnnotationRenderer.draw(layer, in: context)
        context.restoreGState()
    }
}
