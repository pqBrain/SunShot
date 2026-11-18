public import CoreGraphics
public import Foundation
import ImageIO
import UniformTypeIdentifiers

/// S17: Sunshot's app icon, drawn in code (no shipped artwork): a warm sunrise squircle with a white sun held in
/// a capture viewfinder. `scripts/make-app-icon.sh` compiles this file on its own to write `AppIcon.icns`, so it
/// depends on Apple frameworks only.
public enum AppIconArtwork {
    /// The `.iconset` entries `iconutil` expects: file name and pixel size.
    public static let iconsetEntries: [(name: String, pixels: Int)] = [16, 32, 128, 256, 512].flatMap { points in
        [("icon_\(points)x\(points).png", points), ("icon_\(points)x\(points)@2x.png", points * 2)]
    }

    /// The icon at `pixels` × `pixels` (sRGB, transparent outside the squircle). Small sizes get heavier strokes
    /// so the viewfinder still reads at 16 px.
    public static func image(pixels: Int) -> CGImage? {
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)
        // Flip to a top-left origin so the layout reads like the design grid.
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        draw(in: context, space: space, weight: pixels <= 16 ? 2 : pixels < 64 ? 1.5 : 1)
        return context.makeImage()
    }

    /// PNG data of `image(pixels:)`.
    public static func pngData(pixels: Int) -> Data? {
        guard let image = image(pixels: pixels) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Drawing (1024-unit grid, top-left origin)

    /// The macOS icon grid: an 824-unit squircle centred on the 1024 canvas (room for the shadow).
    static let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

    private static func draw(in context: CGContext, space: CGColorSpace, weight: CGFloat) {
        let shape = squircle(in: tile)
        // Soft drop shadow under the tile.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -12), blur: 28,
            color: CGColor(srgbRed: 0.35, green: 0.15, blue: 0.05, alpha: 0.30))
        context.addPath(shape)
        context.setFillColor(CGColor(srgbRed: 1, green: 0.62, blue: 0.38, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        sky(in: context, space: space)
        sun(in: context, space: space, weight: weight)
        viewfinder(in: context, weight: weight)
        glassRim(in: context, shape: shape, space: space)
        context.restoreGState()
    }

    /// Morning sky: pale gold at the top warming to coral at the bottom.
    private static func sky(in context: CGContext, space: CGColorSpace) {
        let colors = [
            CGColor(srgbRed: 1.00, green: 0.80, blue: 0.36, alpha: 1),
            CGColor(srgbRed: 1.00, green: 0.58, blue: 0.33, alpha: 1),
            CGColor(srgbRed: 0.93, green: 0.36, blue: 0.42, alpha: 1),
        ]
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1])
        else { return }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])
    }

    /// The sun: a glow, then a warm-white disc (larger at 32 px; smaller at 16 px so the brackets stay apart).
    private static func sun(in context: CGContext, space: CGColorSpace, weight: CGFloat) {
        let centre = CGPoint(x: 512, y: 512)
        let glow = [
            CGColor(srgbRed: 1, green: 0.96, blue: 0.80, alpha: 0.45),
            CGColor(srgbRed: 1, green: 0.95, blue: 0.80, alpha: 0),
        ]
        // The glow only blurs the disc at small sizes.
        if weight == 1, let gradient = CGGradient(colorsSpace: space, colors: glow as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient, startCenter: centre, startRadius: 130, endCenter: centre, endRadius: 250, options: [])
        }
        let disc = [
            CGColor(srgbRed: 1, green: 1, blue: 0.97, alpha: 1),
            CGColor(srgbRed: 1, green: 0.95, blue: 0.82, alpha: 1),
        ]
        let radius = 136 * (weight == 1.5 ? 1.15 : weight > 1.5 ? 0.9 : 1)
        context.saveGState()
        context.addEllipse(
            in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        if let gradient = CGGradient(colorsSpace: space, colors: disc as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 512, y: 376), end: CGPoint(x: 512, y: 648), options: [])
        }
        context.restoreGState()
    }

    /// Four rounded corner brackets around the sun: the "shot".
    private static func viewfinder(in context: CGContext, weight: CGFloat) {
        let frame = CGRect(x: 262, y: 262, width: 500, height: 500)
        let arm: CGFloat = 132
        let radius: CGFloat = 56
        let path = CGMutablePath()
        for (cx, cy, dx, dy) in [
            (frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
            (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: cx, y: cy + dy * arm))
            path.addArc(
                tangent1End: CGPoint(x: cx, y: cy), tangent2End: CGPoint(x: cx + dx * arm, y: cy), radius: radius)
            path.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
        }
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -6), blur: 16,
            color: CGColor(srgbRed: 0.55, green: 0.20, blue: 0.10, alpha: 0.28))
        context.addPath(path)
        context.setLineWidth(46 * weight)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.strokePath()
        context.restoreGState()
    }

    /// A light top sheen and a thin inner rim, the glass edge of macOS 26 icons.
    private static func glassRim(in context: CGContext, shape: CGPath, space: CGColorSpace) {
        let sheen = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ]
        if let gradient = CGGradient(colorsSpace: space, colors: sheen as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.minY + 300), options: [])
        }
        context.addPath(shape)
        context.setLineWidth(6)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
        context.strokePath()
    }

    /// A superellipse (|x|ⁿ + |y|ⁿ = 1, n = 5), close to the continuous-corner app icon shape.
    static func squircle(in rect: CGRect, exponent: Double = 5, samples: Int = 256) -> CGPath {
        let path = CGMutablePath()
        let half = CGSize(width: rect.width / 2, height: rect.height / 2)
        for step in 0..<samples {
            let angle = Double(step) / Double(samples) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = copysign(pow(abs(cosine), 2 / exponent), cosine)
            let y = copysign(pow(abs(sine), 2 / exponent), sine)
            let point = CGPoint(x: rect.midX + x * half.width, y: rect.midY + y * half.height)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
