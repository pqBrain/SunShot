import CoreGraphics
import CoreText
import Foundation
import SunshotCore

/// Title bars and toolbars: Sunshot's own vector glyphs and the title text. Unscaled units; `geometry.scale` is the
/// UI scale, so every size here grows linearly with it while the content does not.
enum FrameChrome {
    /// Window-control hues (close, minimise, zoom).
    static let trafficLights = [RGBAColor(rgb: 0xFF5F57), RGBAColor(rgb: 0xFEBC2E), RGBAColor(rgb: 0x28C840)]
    static let addressPlaceholder = "example.com"

    static func drawBar(
        geometry: FrameGeometry, palette: ChromePalette, fonts: FontTokens, title: String, context: CGContext
    ) {
        guard let bar = geometry.bar?.cg else { return }
        let s = geometry.scale
        switch geometry.kind {
        case .macWindow:
            drawTrafficLights(barMidY: bar.midY, scale: s, context: context)
            if let rect = geometry.titleRect?.cg {
                let font = FrameFonts.font(fonts.text, size: FrameMetrics.titleFontSize * s)
                FrameText.draw(title, font: font, color: palette.title, in: rect, alignment: .center, context: context)
            }
        case .browserWindow:
            drawTrafficLights(barMidY: bar.midY, scale: s, context: context)
            drawNavigation(geometry: geometry, palette: palette, context: context)
            drawAddressField(geometry: geometry, palette: palette, fonts: fonts, title: title, context: context)
        case .winWindow:
            if let rect = geometry.titleRect?.cg {
                let font = FrameFonts.font(fonts.text, size: FrameMetrics.addressFontSize * s)
                FrameText.draw(title, font: font, color: palette.title, in: rect, alignment: .leading, context: context)
            }
            drawCaptionButtons(geometry: geometry, palette: palette, context: context)
        case .none, .card, .stack, .stack2, .thickBorder:
            break
        }
    }

    static func drawTrafficLights(barMidY: CGFloat, scale: Double, context: CGContext) {
        let diameter = FrameMetrics.trafficLightDiameter * scale
        var x = FrameMetrics.trafficLightInset * scale
        for color in trafficLights {
            let rect = CGRect(x: x, y: barMidY - diameter / 2, width: diameter, height: diameter)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
            context.setLineWidth(0.5 * scale)
            context.strokeEllipse(in: rect.insetBy(dx: 0.25 * scale, dy: 0.25 * scale))
            x += diameter + FrameMetrics.trafficLightGap * scale
        }
    }

    /// Back and forward chevrons between the window controls and the address field.
    static func drawNavigation(geometry: FrameGeometry, palette: ChromePalette, context: CGContext) {
        guard let bar = geometry.bar?.cg else { return }
        let s = geometry.scale
        let start = FrameMetrics.trafficLightInset * s + geometry.trafficLightsWidth + 18 * s
        let half = 5 * s
        context.saveGState()
        context.setLineWidth(1.6 * s)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for (index, pointsLeft) in [true, false].enumerated() {
            let centre = CGPoint(x: start + CGFloat(index) * 22 * s, y: bar.midY)
            let tip = pointsLeft ? -half / 1.6 : half / 1.6
            context.setStrokeColor((index == 0 ? palette.glyph : palette.glyph.withAlpha(0.45)).cgColor)
            context.move(to: CGPoint(x: centre.x - tip, y: centre.y - half))
            context.addLine(to: CGPoint(x: centre.x + tip, y: centre.y))
            context.addLine(to: CGPoint(x: centre.x - tip, y: centre.y + half))
            context.strokePath()
        }
        context.restoreGState()
    }

    static func drawAddressField(
        geometry: FrameGeometry, palette: ChromePalette, fonts: FontTokens, title: String, context: CGContext
    ) {
        guard let field = geometry.addressField?.cg, let textRect = geometry.titleRect?.cg else { return }
        let s = geometry.scale
        let radius = min(8 * s, field.height / 2)
        context.addPath(CGPath(roundedRect: field, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(palette.field.cgColor)
        context.fillPath()

        let font = FrameFonts.font(fonts.text, size: FrameMetrics.addressFontSize * s)
        let text = title.isEmpty ? addressPlaceholder : title
        let color = title.isEmpty ? palette.glyph : palette.title
        let width = FrameText.draw(text, font: font, color: color, in: textRect, alignment: .center, context: context)
        drawLock(
            at: CGPoint(x: textRect.midX - CGFloat(width) / 2 - 10 * s, y: field.midY), scale: s,
            color: palette.accent, context: context)
    }

    /// Small padlock (secure-site glyph) in the accent colour.
    static func drawLock(at centre: CGPoint, scale s: Double, color: RGBAColor, context: CGContext) {
        let body = CGRect(x: centre.x - 3.5 * s, y: centre.y - 0.5 * s, width: 7 * s, height: 5.5 * s)
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: body, cornerWidth: 1.2 * s, cornerHeight: 1.2 * s, transform: nil))
        context.fillPath()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.3 * s)
        context.addArc(
            center: CGPoint(x: centre.x, y: body.minY), radius: 2.3 * s, startAngle: 0, endAngle: .pi,
            clockwise: true)
        context.strokePath()
        context.restoreGState()
    }

    /// Minimise, maximise and close glyphs, right-aligned.
    static func drawCaptionButtons(geometry: FrameGeometry, palette: ChromePalette, context: CGContext) {
        guard let bar = geometry.bar?.cg else { return }
        let s = geometry.scale
        let button = geometry.winButtonWidth
        let half = 5 * s
        context.saveGState()
        context.setStrokeColor(palette.title.cgColor)
        context.setLineWidth(1 * s)
        for index in 0..<3 {
            let centre = CGPoint(x: bar.maxX - button * (2.5 - Double(index)), y: bar.midY)
            switch index {
            case 0:
                context.move(to: CGPoint(x: centre.x - half, y: centre.y))
                context.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
            case 1:
                context.addRect(CGRect(x: centre.x - half, y: centre.y - half, width: 2 * half, height: 2 * half))
            default:
                context.move(to: CGPoint(x: centre.x - half, y: centre.y - half))
                context.addLine(to: CGPoint(x: centre.x + half, y: centre.y + half))
                context.move(to: CGPoint(x: centre.x + half, y: centre.y - half))
                context.addLine(to: CGPoint(x: centre.x - half, y: centre.y + half))
            }
            context.strokePath()
        }
        context.restoreGState()
    }
}

/// Single-line text, truncated with "…" to fit, vertically centred.
enum FrameText {
    enum Alignment { case leading, center }

    /// Draws `text` and returns the drawn width.
    @discardableResult
    static func draw(
        _ text: String, font: CTFont, color: RGBAColor, in rect: CGRect, alignment: Alignment, context: CGContext
    ) -> Double {
        guard !text.isEmpty, rect.width > 1 else { return 0 }
        let line = truncatedLine(text, font: font, color: color, maxWidth: Double(rect.width))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let x = alignment == .center ? rect.midX - CGFloat(width) / 2 : rect.minX
        let baseline = rect.midY + (ascent - descent) / 2
        context.saveGState()
        context.clip(to: rect.insetBy(dx: 0, dy: -rect.height))
        // The context is flipped (y down); flip glyphs back upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
        return width
    }

    static func truncatedLine(_ text: String, font: CTFont, color: RGBAColor, maxWidth: Double) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        guard CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth else { return line }
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, maxWidth, .end, token) ?? line
    }
}
