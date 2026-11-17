public import CoreGraphics
public import Foundation
public import SunshotCore

/// A user image used as a backdrop: the original bytes (kept in the document) and the decoded pixels (decoded
/// once at import, then reused by every render). Identity-compared so undo snapshots stay cheap.
public struct MediaAsset: Equatable, Sendable {
    public let reference: MediaReference
    public let data: Data
    public let image: CGImage

    public init(reference: MediaReference, data: Data, image: CGImage) {
        self.reference = reference
        self.data = data
        self.image = image
    }

    public static func == (lhs: MediaAsset, rhs: MediaAsset) -> Bool { lhs.reference == rhs.reference }
}

/// Checkerboard drawn behind a transparent backdrop in the preview only (never in exports or copies).
public struct TransparencyGrid: Hashable, Sendable {
    public var light: RGBAColor
    public var dark: RGBAColor
    /// Square side in canvas pixels.
    public var squareSize: Double

    public init(light: RGBAColor, dark: RGBAColor, squareSize: Double = TransparencyGrid.defaultSquareSize) {
        self.light = light
        self.dark = dark
        self.squareSize = max(1, squareSize)
    }

    /// 8 pt on a 2× display at 1:1 preview.
    public static let defaultSquareSize: Double = 16
    public static let standard = TransparencyGrid(light: .white, dark: RGBAColor(rgb: 0xDCDCE1))
}

enum BackdropRenderer {
    /// Draws the grid (preview only) and then the backdrop over it. The context has a top-left, canvas-unit CTM.
    static func draw(
        _ backdrop: Backdrop, size: PixelSize, media: [String: MediaAsset], grid: TransparencyGrid?,
        in context: CGContext
    ) {
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.clear(bounds)
        if let grid, !backdrop.isOpaque { drawGrid(grid, in: bounds, context: context) }
        switch backdrop {
        case .none:
            break
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        case .gradient(let spec):
            PixelFill.gradient(spec, into: context)
        case .image(.wallpaper(let wallpaper)):
            PixelFill.wallpaper(wallpaper, into: context)
        case .image(.file(let reference)):
            if let asset = media[reference.id] {
                drawCover(asset.image, in: bounds, context: context)
            } else {
                // The bytes are missing (should not happen): fall back to the default colour, never garbage.
                context.setFillColor(SunshotDefaults.backdropColor.cgColor)
                context.fill(bounds)
            }
        }
    }

    private static func drawGrid(_ grid: TransparencyGrid, in bounds: CGRect, context: CGContext) {
        context.setFillColor(grid.light.cgColor)
        context.fill(bounds)
        let side = grid.squareSize
        let columns = Int((bounds.width / side).rounded(.up))
        let rows = Int((bounds.height / side).rounded(.up))
        var squares: [CGRect] = []
        squares.reserveCapacity(columns * rows / 2 + 1)
        for row in 0..<rows {
            for column in stride(from: row % 2, to: columns, by: 2) {
                squares.append(CGRect(x: Double(column) * side, y: Double(row) * side, width: side, height: side))
            }
        }
        context.setFillColor(grid.dark.cgColor)
        context.fill(squares)
    }

    /// Aspect-preserving "fill": the image covers the canvas, centred, cropping the overflow.
    static func coverRect(imageWidth: Int, imageHeight: Int, in bounds: CGRect) -> CGRect {
        let scale = max(bounds.width / Double(imageWidth), bounds.height / Double(imageHeight))
        let width = Double(imageWidth) * scale
        let height = Double(imageHeight) * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    private static func drawCover(_ image: CGImage, in bounds: CGRect, context: CGContext) {
        let target = coverRect(imageWidth: image.width, imageHeight: image.height, in: bounds)
        context.saveGState()
        context.clip(to: bounds)
        // Images draw bottom-up; undo the canvas flip locally so the backdrop is not mirrored.
        context.translateBy(x: 0, y: target.minY + target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: target)
        context.restoreGState()
    }
}
