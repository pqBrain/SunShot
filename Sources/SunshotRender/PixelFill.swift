import CoreGraphics
import Foundation
import SunshotCore

/// Per-pixel fills written straight into the bitmap (rows run top-down in memory, matching layout coordinates).
///
/// Each pixel is computed in floating point and then dithered: `floor(value + noise)` with deterministic
/// per-pixel noise in `0..<1`, so the output is always one of the two nearest 8-bit levels and slow gradients
/// between close colours don't form visible bands.
enum PixelFill {
    /// Fills the whole context with `spec`. Returns false if the context has no accessible bitmap.
    @discardableResult
    static func gradient(_ spec: GradientSpec, into context: CGContext) -> Bool {
        guard let mapper = GradientMapper(spec, width: context.width, height: context.height) else { return false }
        let table = ColorTable(spec, length: mapper.length)
        let composite = !spec.isOpaque
        return fill(context) { x, y in
            table.color(at: mapper.position(x: x, y: y))
        } store: { pixel, color, noise in
            composite ? pixel.storeOver(color, noise: noise) : pixel.store(color, noise: noise)
        }
    }

    /// Fills the whole context with a generated wallpaper drawn with "fill" (cover) scaling.
    @discardableResult
    static func wallpaper(_ wallpaper: Wallpaper, into context: CGContext) -> Bool {
        let width = context.width
        let height = context.height
        guard let mapper = GradientMapper(wallpaper.base, width: width, height: height) else { return false }
        let table = ColorTable(wallpaper.base, length: mapper.length)
        let fields = wallpaper.fields.map(FieldSample.init)
        // Cover: the 16:10 design space scaled so it covers the canvas, centred.
        let scale = max(Double(width) / Wallpaper.designWidth, Double(height) / Wallpaper.designHeight)
        let originX = Double(width) / 2 - Wallpaper.designWidth / 2 * scale
        let originY = Double(height) / 2 - Wallpaper.designHeight / 2 * scale
        return fill(context) { x, y in
            var color = table.color(at: mapper.position(x: x, y: y))
            let u = (Double(x) + 0.5 - originX) / scale
            let v = (Double(y) + 0.5 - originY) / scale
            for field in fields {
                let dx = u - field.x
                let dy = v - field.y
                let weight = Float(field.field.weight(atDistanceSquared: dx * dx + dy * dy))
                if weight > 0 { color = color + (field.color - color) * weight }
            }
            return color
        } store: { pixel, color, noise in
            pixel.store(color, noise: noise)
        }
    }

    private struct FieldSample {
        let field: ColorField
        let x: Double
        let y: Double
        let color: SIMD4<Float>

        init(_ field: ColorField) {
            self.field = field
            x = field.x
            y = field.y
            color = ColorTable.premultiplied(field.color)
        }
    }

    /// Runs `shade` for every pixel (bands of rows in parallel) and stores the result with dither noise.
    private static func fill(
        _ context: CGContext, shade: (Int, Int) -> SIMD4<Float>,
        store: (UnsafeMutablePointer<UInt8>, SIMD4<Float>, Float) -> Void
    ) -> Bool {
        guard let data = context.data, context.bitsPerPixel == 32 else { return false }
        let width = context.width
        let height = context.height
        let rowBytes = context.bytesPerRow
        let base = data.assumingMemoryBound(to: UInt8.self)
        let bandHeight = 32
        let bands = (height + bandHeight - 1) / bandHeight
        withoutActuallyEscaping(shade) { shade in
            withoutActuallyEscaping(store) { store in
                let work = BandWork(base: base, shade: shade, store: store)
                DispatchQueue.concurrentPerform(iterations: bands) { band in
                    let rows = (band * bandHeight)..<min(height, (band + 1) * bandHeight)
                    for y in rows {
                        let row = work.base + y * rowBytes
                        for x in 0..<width {
                            work.store(row + x * 4, work.shade(x, y), noise(x, y))
                        }
                    }
                }
            }
        }
        return true
    }

    /// Bands write disjoint rows of the bitmap and the closures only read shared immutable state.
    // SAFETY: each concurrentPerform iteration touches only its own rows; shade/store capture immutable values.
    private struct BandWork: @unchecked Sendable {
        let base: UnsafeMutablePointer<UInt8>
        let shade: (Int, Int) -> SIMD4<Float>
        let store: (UnsafeMutablePointer<UInt8>, SIMD4<Float>, Float) -> Void
    }

    /// Deterministic noise in `0..<1` for pixel (x, y) (integer hash, so preview and export match exactly).
    @inline(__always)
    static func noise(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x) &* 0x8DA6_B343 ^ UInt32(truncatingIfNeeded: y) &* 0xD816_3841
        h ^= h >> 15
        h &*= 0x2C1B_3C6D
        h ^= h >> 12
        h &*= 0x297A_2D39
        h ^= h >> 15
        return Float(h >> 8) / 16_777_216
    }
}

/// Maps a pixel to its position (0…1) along a gradient, in pixel space so every scale is proportional.
struct GradientMapper {
    private let kind: GradientKind
    private let dx: Double
    private let dy: Double
    private let centerX: Double
    private let centerY: Double
    /// Gradient length in pixels (linear: the projection of the canvas on the axis; radial: centre → corner).
    let length: Double

    init?(_ spec: GradientSpec, width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        let w = Double(width)
        let h = Double(height)
        kind = spec.kind
        centerX = w / 2
        centerY = h / 2
        switch spec.kind {
        case .linear:
            // 0° points up (bottom → top), clockwise; y grows downward in pixel space.
            let radians = spec.angle * .pi / 180
            let sine = sin(radians)
            let cosine = cos(radians)
            length = abs(w * sine) + abs(h * cosine)
            dx = sine / length
            dy = -cosine / length
        case .radial:
            length = (centerX * centerX + centerY * centerY).squareRoot()
            dx = 1 / length
            dy = 1 / length
        }
    }

    @inline(__always)
    func position(x: Int, y: Int) -> Double {
        let px = Double(x) + 0.5 - centerX
        let py = Double(y) + 0.5 - centerY
        switch kind {
        case .linear: return px * dx + py * dy + 0.5
        case .radial: return (px * px + py * py).squareRoot() * dx
        }
    }
}

/// Premultiplied colours (0…255) sampled along the gradient, two entries per pixel of gradient length.
struct ColorTable {
    private let entries: [SIMD4<Float>]
    private let last: Double

    init(_ spec: GradientSpec, length: Double) {
        let count = min(max(Int((length * 2).rounded(.up)), 2), 32_768)
        last = Double(count - 1)
        entries = (0..<count).map { Self.premultiplied(spec.color(at: Double($0) / Double(count - 1))) }
    }

    @inline(__always)
    func color(at position: Double) -> SIMD4<Float> {
        let index = Int(min(max(position, 0), 1) * last + 0.5)
        return entries[index]
    }

    /// Values within float error of an exact 8-bit level snap to it, so a flat colour dithers to exactly itself.
    static func premultiplied(_ color: RGBAColor) -> SIMD4<Float> {
        let alpha = color.alpha
        func level(_ value: Double) -> Float {
            let scaled = value * 255
            let nearest = scaled.rounded()
            return Float(abs(scaled - nearest) < 1e-4 ? nearest : scaled)
        }
        return SIMD4(level(color.red * alpha), level(color.green * alpha), level(color.blue * alpha), level(alpha))
    }
}

extension UnsafeMutablePointer<UInt8> {
    /// Stores a premultiplied colour, dithered, keeping colour ≤ alpha.
    @inline(__always)
    func store(_ color: SIMD4<Float>, noise: Float) {
        let alpha = Self.quantize(color.w, noise)
        self[0] = Swift.min(Self.quantize(color.x, noise), alpha)
        self[1] = Swift.min(Self.quantize(color.y, noise), alpha)
        self[2] = Swift.min(Self.quantize(color.z, noise), alpha)
        self[3] = alpha
    }

    /// Composites a premultiplied colour over what is already there (e.g. the preview's checkerboard).
    @inline(__always)
    func storeOver(_ color: SIMD4<Float>, noise: Float) {
        let keep = 1 - color.w / 255
        let below = SIMD4<Float>(Float(self[0]), Float(self[1]), Float(self[2]), Float(self[3]))
        store(color + below * keep, noise: noise)
    }

    @inline(__always)
    private static func quantize(_ value: Float, _ noise: Float) -> UInt8 {
        UInt8(Swift.min(Swift.max((value + noise).rounded(.down), 0), 255))
    }
}
