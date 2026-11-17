import CoreGraphics
import CoreImage
import Foundation
import SunshotCore

/// Draws the content "silhouette" (clipped content and border; S5 frame chrome belongs inside it too) through
/// the document's `ContentTransform`, with the shadow cast in canvas space.
///
/// - Identity: exactly the pre-S6 drawing sequence, so output stays byte-identical.
/// - Flat (no tilt): an affine CTM around the silhouette; CoreGraphics draws it directly (crisp, no resampling).
/// - Tilted: the silhouette is drawn upright into an offscreen bitmap at output resolution, warped onto its
///   projected quad with CoreImage's perspective transform, and drawn back in device space with the shadow, so
///   the shadow follows the warped alpha. Shadow offsets are device-space in CoreGraphics, so the shadow
///   direction stays tied to the light source whatever the rotation; its size scales with zoom.
enum ContentTransformRenderer {
    /// Transparent margin (offscreen pixels) around the silhouette so warped edges are anti-aliased.
    static let offscreenMargin = 2
    /// The offscreen silhouette never exceeds this many pixels on its long side (extreme zoom on huge content);
    /// beyond it the warp upsamples slightly instead of allocating gigabytes.
    static let maxOffscreenSide = 8192
    /// From this many output pixels per content pixel on, flat content is sampled nearest-neighbour.
    static let nearestNeighbourZoom: Double = 3

    /// CoreImage context shared by every render (thread-safe; creating one per render is expensive).
    static let ciContext: CIContext = {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        var options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let sRGB { options[.outputColorSpace] = sRGB }
        return CIContext(options: options)
    }()

    /// - Parameters:
    ///   - bounds: the silhouette's local bounds in unscaled content units (the content rect is
    ///     `0, 0, contentRect.width / styleScale, contentRect.height / styleScale`).
    ///   - silhouette: draws in local units into the given context; must not set a shadow.
    static func draw(
        transform: ContentTransform, layout: CanvasLayout, shadow: ShadowMetrics, scale: Double, bounds: CGRect,
        in context: CGContext, silhouette: (CGContext) -> Void
    ) {
        let rect = layout.contentRect
        let style = layout.styleScale.isFinite && layout.styleScale > 0 ? layout.styleScale : 1
        let metrics = shadow.scaled(by: scale * style * transform.scale)

        if !transform.isFlat {
            drawTilted(
                transform: transform, layout: layout, style: style, metrics: metrics, scale: scale, bounds: bounds,
                in: context, silhouette: silhouette)
            return
        }
        context.saveGState()
        if transform.isIdentity {
            context.translateBy(x: rect.x, y: rect.y)
            context.scaleBy(x: style, y: style)
        } else {
            let projection = ContentProjection(contentRect: rect, canvasSize: layout.canvasSize, transform: transform)
            context.translateBy(x: projection.center.x, y: projection.center.y)
            context.rotate(by: transform.rotation * .pi / 180)
            context.scaleBy(x: style * transform.scale, y: style * transform.scale)
            context.translateBy(x: -rect.width / style / 2, y: -rect.height / style / 2)
            // Strongly zoomed content keeps crisp pixels (and exact edges) instead of a soft bilinear blur.
            if style * transform.scale * scale >= nearestNeighbourZoom { context.interpolationQuality = .none }
        }
        withShadow(metrics, in: context) { silhouette(context) }
        context.restoreGState()
    }

    private static func withShadow(_ metrics: ShadowMetrics, in context: CGContext, _ body: () -> Void) {
        guard metrics.opacity > 0 else { return body() }
        // Shadow offsets are in device space (y up), unaffected by our flipped CTM: negate y to fall down.
        context.setShadow(
            offset: CGSize(width: metrics.offsetX, height: -metrics.offsetY), blur: metrics.blur,
            color: CGColor(gray: 0, alpha: metrics.opacity))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
    }

    // MARK: Perspective

    private static func drawTilted(
        transform: ContentTransform, layout: CanvasLayout, style: Double, metrics: ShadowMetrics, scale: Double,
        bounds: CGRect, in context: CGContext, silhouette: (CGContext) -> Void
    ) {
        guard bounds.width > 0, bounds.height > 0,
            let warped = warpedSilhouette(
                transform: transform, layout: layout, style: style, scale: scale, bounds: bounds,
                silhouette: silhouette)
        else { return }
        context.saveGState()
        // Device space: 1 unit = 1 output pixel, y up.
        context.concatenate(context.ctm.inverted())
        if metrics.opacity > 0 {
            context.setShadow(
                offset: CGSize(width: metrics.offsetX, height: -metrics.offsetY), blur: metrics.blur,
                color: CGColor(gray: 0, alpha: metrics.opacity))
        }
        context.draw(warped.image, in: warped.deviceRect)
        context.restoreGState()
    }

    /// The silhouette warped onto its projected quad, cropped to the canvas, in device pixels (y up).
    static func warpedSilhouette(
        transform: ContentTransform, layout: CanvasLayout, style: Double, scale: Double, bounds: CGRect,
        silhouette: (CGContext) -> Void
    ) -> (image: CGImage, deviceRect: CGRect)? {
        let canvasWidth = Double(ExportPlan.scaled(layout.canvasSize.width, by: scale))
        let canvasHeight = Double(ExportPlan.scaled(layout.canvasSize.height, by: scale))
        // Offscreen resolution: the silhouette's flat size at output scale, capped.
        let wanted = style * transform.scale * scale
        let cap = Double(min(maxOffscreenSide, max(Int(2 * max(canvasWidth, canvasHeight)), 256)))
        let pixelsPerUnit = min(wanted, cap / max(bounds.width, bounds.height))
        guard pixelsPerUnit.isFinite, pixelsPerUnit > 0,
            let upright = drawUpright(bounds: bounds, pixelsPerUnit: pixelsPerUnit, silhouette: silhouette)
        else { return nil }

        let marginX = Double(offscreenMargin) / upright.scaleX
        let marginY = Double(offscreenMargin) / upright.scaleY
        let projection = ContentProjection(
            contentRect: layout.contentRect, canvasSize: layout.canvasSize, transform: transform)
        // Local silhouette units → projection local units (canvas px before zoom) → device pixels (y up).
        func device(_ x: Double, _ y: Double) -> CGPoint {
            let point = projection.project(LayoutPoint(x: x * style, y: y * style))
            return CGPoint(x: point.x * scale, y: canvasHeight - point.y * scale)
        }
        let (minX, minY) = (bounds.minX - marginX, bounds.minY - marginY)
        let (maxX, maxY) = (bounds.maxX + marginX, bounds.maxY + marginY)
        let corners = [device(minX, minY), device(maxX, minY), device(maxX, maxY), device(minX, maxY)]
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        let input = CIImage(cgImage: upright.image)
        guard let filter = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: corners[0]), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: corners[1]), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: corners[2]), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: corners[3]), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else { return nil }

        let quadBounds = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let crop = quadBounds.integral.intersection(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1,
            let image = ciContext.createCGImage(
                output, from: crop, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        else { return nil }
        return (image, crop)
    }

    /// The silhouette drawn flat (top-left origin) at `pixelsPerUnit`, with a transparent margin.
    private static func drawUpright(
        bounds: CGRect, pixelsPerUnit: Double, silhouette: (CGContext) -> Void
    )
        -> (image: CGImage, scaleX: Double, scaleY: Double)?
    {
        let margin = Double(offscreenMargin)
        let width = Int((bounds.width * pixelsPerUnit).rounded(.up)) + 2 * offscreenMargin
        let height = Int((bounds.height * pixelsPerUnit).rounded(.up)) + 2 * offscreenMargin
        guard let offscreen = Renderer.makeContext(width: width, height: height) else { return nil }
        offscreen.translateBy(x: 0, y: CGFloat(height))
        offscreen.scaleBy(x: 1, y: -1)
        offscreen.interpolationQuality = .high
        // Exact fit: stretch the margin-inset area to the rounded-up pixel size so the quad maps 1:1.
        let sx = (Double(width) - 2 * margin) / bounds.width
        let sy = (Double(height) - 2 * margin) / bounds.height
        offscreen.translateBy(x: margin, y: margin)
        offscreen.scaleBy(x: sx, y: sy)
        offscreen.translateBy(x: -bounds.minX, y: -bounds.minY)
        silhouette(offscreen)
        guard let image = offscreen.makeImage() else { return nil }
        return (image, sx, sy)
    }
}
