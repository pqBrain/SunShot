import CoreGraphics
import Foundation
import SunshotCore

@testable import SunshotRender

/// Backdrop test helpers: quadrant images whose orientation and centre are easy to check, and pixel maths.
enum BackdropFixtures {
    static let topLeft: [UInt8] = [230, 40, 40, 255]
    static let topRight: [UInt8] = [40, 180, 60, 255]
    static let bottomLeft: [UInt8] = [40, 70, 220, 255]
    static let bottomRight: [UInt8] = [240, 200, 30, 255]
    static let centre: [UInt8] = [200, 40, 200, 255]

    /// Four coloured quadrants with a magenta square at the centre (side = 1/5 of the shorter edge).
    static func quadrants(width: Int, height: Int) throws -> CGImage {
        try Fixtures.draw(width: width, height: height) { context in
            // CGContext origin is bottom-left: "top" rows are the high y values.
            let halfW = CGFloat(width) / 2
            let halfH = CGFloat(height) / 2
            let fills: [([UInt8], CGRect)] = [
                (topLeft, CGRect(x: 0, y: halfH, width: halfW, height: halfH)),
                (topRight, CGRect(x: halfW, y: halfH, width: halfW, height: halfH)),
                (bottomLeft, CGRect(x: 0, y: 0, width: halfW, height: halfH)),
                (bottomRight, CGRect(x: halfW, y: 0, width: halfW, height: halfH)),
            ]
            for (color, rect) in fills {
                context.setFillColor(cgColor(color))
                context.fill(rect)
            }
            let side = CGFloat(min(width, height)) / 5
            context.setFillColor(cgColor(centre))
            context.fill(CGRect(x: halfW - side / 2, y: halfH - side / 2, width: side, height: side))
        }
    }

    static func cgColor(_ rgba: [UInt8]) -> CGColor {
        CGColor(
            srgbRed: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255, blue: CGFloat(rgba[2]) / 255,
            alpha: CGFloat(rgba[3]) / 255)
    }

    /// A media asset (as stored by an import) for `image`.
    static func asset(_ image: CGImage, id: String = "fixture") throws -> MediaAsset {
        let reference = MediaReference(
            id: id, fileName: "\(id).png", pixelSize: PixelSize(width: image.width, height: image.height))
        return MediaAsset(reference: reference, data: try ImageCodec.pngData(image), image: image)
    }

    static func close(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int = 2) -> Bool {
        zip(lhs, rhs).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    /// Un-premultiplied RGBA (as a PNG stores it) from a premultiplied pixel.
    static func unpremultiplied(_ pixel: [UInt8]) -> [Int] {
        let alpha = Int(pixel[3])
        guard alpha > 0 else { return [0, 0, 0, 0] }
        return pixel.prefix(3).map { (Int($0) * 255 + alpha / 2) / alpha } + [alpha]
    }

    static func gradient(
        _ stops: (Double, UInt32)..., kind: GradientKind = .linear, angle: Double = 90
    )
        -> GradientSpec
    {
        GradientSpec(
            kind: kind, angle: angle, stops: stops.map { GradientStop(position: $0.0, color: RGBAColor(rgb: $0.1)) })
    }
}
