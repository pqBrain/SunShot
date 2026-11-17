import CoreGraphics
import CoreText
import Foundation
import SunshotCore

/// Draws annotations as vector shapes. Called by `Renderer` inside the content's coordinate system (content pixels,
/// top-left origin, y down) after the content image and inside its clip, so preview and export share it and every
/// shape is drawn at the output resolution.
enum AnnotationRenderer {
    /// Redactions are not drawn here: `RedactionRenderer.apply` already rewrote the content pixels beneath.
    static func draw(_ layer: AnnotationLayer, in context: CGContext) {
        guard !layer.isEmpty else { return }
        for annotation in layer.items where annotation.isValid && annotation.kind != .redact {
            context.saveGState()
            rotate(context, for: annotation)
            draw(annotation, label: layer.stepLabel(for: annotation.id) ?? "", in: context)
            context.restoreGState()
        }
    }

    static func rotate(_ context: CGContext, for annotation: Annotation) {
        guard annotation.rotation != 0 else { return }
        let center = annotation.center
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: annotation.rotation * .pi / 180)
        context.translateBy(x: -center.x, y: -center.y)
    }

    private static func draw(_ annotation: Annotation, label: String, in context: CGContext) {
        let box = cgRect(annotation.bounds)
        switch annotation.kind {
        case .pen:
            stroke(annotation, in: context)
        case .highlighter:
            context.setBlendMode(.multiply)
            stroke(annotation, alpha: AnnotationDefaults.highlighterAlpha, in: context)
        case .arrow:
            arrow(annotation, in: context)
        case .rectangle:
            if annotation.filled {
                context.setFillColor(annotation.color.cgColor)
                context.fill(box)
            } else {
                applyStroke(annotation, in: context)
                context.setLineJoin(.miter)
                context.stroke(box)
            }
        case .text:
            TextDrawing.draw(annotation, in: context)
        case .step:
            context.setFillColor(annotation.color.cgColor)
            context.fillEllipse(in: box)
            TextDrawing.drawCentered(
                label, in: box, fontSize: min(box.width, box.height) * 0.55, bold: true,
                color: contrasting(annotation.color), context: context)
        case .sticker:
            TextDrawing.drawCentered(
                annotation.text, in: box, fontSize: min(box.width, box.height) * 0.8, bold: false,
                color: CGColor(gray: 0, alpha: 1), context: context)
        case .redact:
            break
        }
    }

    static func cgRect(_ rect: LayoutRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    /// White on dark colours, near-black on light ones.
    static func contrasting(_ color: RGBAColor) -> CGColor {
        let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        return luminance > 0.6 ? CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1) : CGColor(gray: 1, alpha: 1)
    }

    private static func applyStroke(_ annotation: Annotation, alpha: Double = 1, in context: CGContext) {
        let width = annotation.lineWidth
        var color = annotation.color
        color.alpha *= alpha
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.lineStyle {
        case .solid: break
        case .dashed: context.setLineDash(phase: 0, lengths: [width * 2.5, width * 2.5])
        case .dotted: context.setLineDash(phase: 0, lengths: [0, width * 2])
        }
    }

    /// Smoothed freehand stroke: quadratic curves through the midpoints of consecutive samples.
    static func smoothPath(_ points: [AnnotationPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        guard points.count > 2 else {
            let last = points[points.count - 1]
            path.addLine(to: CGPoint(x: last.x, y: last.y))
            return path
        }
        for index in 1..<(points.count - 1) {
            let control = points[index]
            let next = points[index + 1]
            path.addQuadCurve(
                to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2),
                control: CGPoint(x: control.x, y: control.y))
        }
        let last = points[points.count - 1]
        path.addLine(to: CGPoint(x: last.x, y: last.y))
        return path
    }

    private static func stroke(_ annotation: Annotation, alpha: Double = 1, in context: CGContext) {
        if annotation.points.count == 1, let dot = annotation.points.first {
            var color = annotation.color
            color.alpha *= alpha
            context.setFillColor(color.cgColor)
            let radius = annotation.lineWidth / 2
            context.fillEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
            return
        }
        applyStroke(annotation, alpha: alpha, in: context)
        context.addPath(smoothPath(annotation.points))
        context.strokePath()
    }

    private static func arrow(_ annotation: Annotation, in context: CGContext) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let length = start.distance(to: end)
        guard length > 0 else { return }
        let direction = (x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let head = min(AnnotationGeometry.arrowHeadLength(lineWidth: annotation.lineWidth), length)
        let halfWidth = head * 0.45
        let base = (x: end.x - direction.x * head, y: end.y - direction.y * head)
        // The shaft stops inside the head so its round cap never pokes through the tip.
        let shaftEnd = (x: end.x - direction.x * head * 0.6, y: end.y - direction.y * head * 0.6)
        applyStroke(annotation, in: context)
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y))
        context.strokePath()

        context.setFillColor(annotation.color.cgColor)
        context.move(to: CGPoint(x: end.x, y: end.y))
        context.addLine(to: CGPoint(x: base.x - direction.y * halfWidth, y: base.y + direction.x * halfWidth))
        context.addLine(to: CGPoint(x: base.x + direction.y * halfWidth, y: base.y - direction.x * halfWidth))
        context.closePath()
        context.fillPath()
    }
}

/// CoreText drawing in a y-down context.
enum TextDrawing {
    static func font(size: Double, bold: Bool) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func metrics(_ line: CTLine) -> (width: Double, ascent: Double, descent: Double) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (width, ascent, descent)
    }

    static func draw(_ line: CTLine, x: Double, baseline: Double, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Multi-line text from the top of the annotation box, aligned within its width.
    static func draw(_ annotation: Annotation, in context: CGContext) {
        let box = annotation.bounds
        let font = font(size: annotation.fontSize, bold: false)
        let lineHeight = annotation.fontSize * TextMetrics.lineHeightFactor
        let lines = annotation.text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, text) in lines.enumerated() {
            let ctLine = line(String(text), font: font, color: annotation.color.cgColor)
            let size = metrics(ctLine)
            let x: Double =
                switch annotation.alignment {
                case .left: box.x
                case .center: box.midX - size.width / 2
                case .right: box.x + box.width - size.width
                }
            let baseline = box.y + Double(index) * lineHeight + (lineHeight + size.ascent - size.descent) / 2
            draw(ctLine, x: x, baseline: baseline, in: context)
        }
    }

    /// One line centred in `rect` (step labels, emoji).
    static func drawCentered(
        _ text: String, in rect: CGRect, fontSize: Double, bold: Bool, color: CGColor, context: CGContext
    ) {
        guard !text.isEmpty, fontSize > 0 else { return }
        let ctLine = line(text, font: font(size: fontSize, bold: bold), color: color)
        let size = metrics(ctLine)
        draw(ctLine, x: rect.midX - size.width / 2, baseline: rect.midY + (size.ascent - size.descent) / 2, in: context)
    }
}
