import Accelerate
import CoreGraphics
import Foundation
import SunshotCore

/// S8: draws the backdrop with its effects, and the overlay texture above the content.
///
/// Order below the content: backdrop → blur → saturation → pattern → vignette → grain → opacity → underlay.
/// Everything runs on the CPU with deterministic maths (and the same dither as S3), so preview and export are
/// byte-identical. With all effects off the S3 path runs unchanged, so existing renders are byte-identical too.
enum EffectsRenderer {
    /// Strength of full (100 %) grain, in 8-bit levels either side of the colour.
    static let grainLevels: Float = 40
    /// Darkest a vignette or overlay can get (alpha at full intensity).
    static let maxVignetteAlpha = 0.9

    /// Replaces `BackdropRenderer.draw` in `Renderer.render`: the backdrop, its effects, and (preview only) the
    /// checkerboard behind whatever is not opaque.
    static func drawBackdrop(
        _ settings: BackdropSettings, size: PixelSize, media: [String: MediaAsset], grid: TransparencyGrid?,
        in context: CGContext
    ) {
        let effects = settings.effects
        guard !effects.isIdentityBelowContent else {
            BackdropRenderer.draw(settings.backdrop, size: size, media: media, grid: grid, in: context)
            return
        }
        BackdropRenderer.draw(settings.backdrop, size: size, media: media, grid: nil, in: context)
        let geometry = EffectGeometry(canvas: size, pixelWidth: context.width, pixelHeight: context.height)
        if effects.adjustments.blur > 0 {
            BoxBlur.apply(radius: effects.adjustments.blur * geometry.scaleX, to: context)
        }
        BelowContentPass(effects, geometry: geometry).run(on: context)
        if let grid, !settings.backdrop.isOpaque || effects.adjustments.opacity < 1 {
            drawGridBehind(grid, size: size, in: context)
        }
    }

    /// The overlay texture over everything drawn so far (backdrop and content). No-op unless position = above.
    static func drawAboveContent(_ effects: BackdropEffects, size: PixelSize, in context: CGContext) {
        guard effects.drawsAboveContent else { return }
        let geometry = EffectGeometry(canvas: size, pixelWidth: context.width, pixelHeight: context.height)
        let field = OverlayField(effects.overlay.kind, geometry: geometry)
        let opacity = effects.overlay.opacity * maxVignetteAlpha
        PixelPass.run(on: context) { pixel, x, y in
            let alpha = Float(field.shade(u: geometry.u(x), v: geometry.v(y)) * opacity)
            guard alpha > 0 else { return }
            pixel.store(PixelPass.shadow(alpha, over: PixelPass.load(pixel)), noise: PixelFill.noise(x, y))
        }
    }

    /// Draws the checkerboard under the existing pixels (destination-over), preview only.
    private static func drawGridBehind(_ grid: TransparencyGrid, size: PixelSize, in context: CGContext) {
        guard let layer = Renderer.makeContext(width: context.width, height: context.height) else { return }
        layer.translateBy(x: 0, y: CGFloat(context.height))
        layer.scaleBy(
            x: CGFloat(context.width) / CGFloat(size.width), y: -CGFloat(context.height) / CGFloat(size.height))
        BackdropRenderer.draw(.none, size: size, media: [:], grid: grid, in: layer)
        guard let image = layer.makeImage() else { return }
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.saveGState()
        context.setBlendMode(.destinationOver)
        // Images draw bottom-up; undo the canvas flip locally.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: bounds)
        context.restoreGState()
    }
}

/// Saturation, pattern, vignette, grain, opacity and an underlay texture in one pass over the backdrop pixels.
private struct BelowContentPass {
    let effects: BackdropEffects
    let geometry: EffectGeometry

    init(_ effects: BackdropEffects, geometry: EffectGeometry) {
        self.effects = effects
        self.geometry = geometry
    }

    func run(on context: CGContext) {
        let adjustments = effects.adjustments
        let saturation = Float(adjustments.saturation)
        let grain = Float(adjustments.noise) * EffectsRenderer.grainLevels * 2
        let opacity = Float(adjustments.opacity)
        let pattern = effects.pattern.isIdentity ? nil : PatternField(effects.pattern, geometry: geometry)
        let patternColor = ColorTable.premultiplied(effects.pattern.color)
        let patternIntensity = effects.pattern.intensity
        let vignette = effects.vignette.isIdentity ? nil : VignetteField(effects.vignette, geometry: geometry)
        let vignetteColor: SIMD4<Float> =
            effects.vignette.style == .light ? SIMD4(255, 255, 255, 255) : SIMD4(0, 0, 0, 255)
        let vignetteAlpha = effects.vignette.intensity * EffectsRenderer.maxVignetteAlpha
        let underlay =
            effects.overlay.isIdentity || effects.overlay.position == .above
            ? nil : OverlayField(effects.overlay.kind, geometry: geometry)
        let underlayAlpha = effects.overlay.opacity * EffectsRenderer.maxVignetteAlpha
        let geometry = geometry

        PixelPass.run(on: context) { pixel, x, y in
            var color = PixelPass.load(pixel)
            let u = geometry.u(x)
            let v = geometry.v(y)
            if saturation != 1 {
                let luma = 0.2126 * color.x + 0.7152 * color.y + 0.0722 * color.z
                let rgb = SIMD3(luma, luma, luma) + (SIMD3(color.x, color.y, color.z) - luma) * saturation
                color = SIMD4(rgb.x, rgb.y, rgb.z, color.w)
            }
            if let pattern {
                let coverage = Float(pattern.coverage(u: u, v: v) * patternIntensity)
                if coverage > 0 { color = PixelPass.over(patternColor * coverage, color) }
            }
            if let vignette {
                let alpha = Float(vignette.weight(u: u, v: v) * vignetteAlpha)
                if alpha > 0 { color = PixelPass.over(vignetteColor * alpha, color) }
            }
            if grain > 0 {
                let cell = latticeHash(Int(u.rounded(.down)), Int(v.rounded(.down)), seed: 0x6A1)
                let delta = (Float(cell) - 0.5) * grain * color.w / 255
                color += SIMD4(delta, delta, delta, 0)
            }
            if opacity != 1 { color *= opacity }
            if let underlay {
                let alpha = Float(underlay.shade(u: u, v: v) * underlayAlpha)
                if alpha > 0 { color = PixelPass.shadow(alpha, over: color) }
            }
            pixel.store(color, noise: PixelFill.noise(x, y))
        }
    }
}

/// Runs a body for every pixel of a 32-bit bitmap context, bands of rows in parallel (rows top-down in memory).
enum PixelPass {
    @discardableResult
    static func run(on context: CGContext, _ body: (UnsafeMutablePointer<UInt8>, Int, Int) -> Void) -> Bool {
        guard let data = context.data, context.bitsPerPixel == 32 else { return false }
        let width = context.width
        let height = context.height
        let rowBytes = context.bytesPerRow
        let bandHeight = 32
        let bands = (height + bandHeight - 1) / bandHeight
        withoutActuallyEscaping(body) { body in
            let work = PassWork(base: data.assumingMemoryBound(to: UInt8.self), body: body)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                for y in (band * bandHeight)..<min(height, (band + 1) * bandHeight) {
                    let row = work.base + y * rowBytes
                    for x in 0..<width { work.body(row + x * 4, x, y) }
                }
            }
        }
        return true
    }

    // SAFETY: each concurrentPerform iteration touches only its own rows; the body captures immutable values.
    private struct PassWork: @unchecked Sendable {
        let base: UnsafeMutablePointer<UInt8>
        let body: (UnsafeMutablePointer<UInt8>, Int, Int) -> Void
    }

    @inline(__always)
    static func load(_ pixel: UnsafeMutablePointer<UInt8>) -> SIMD4<Float> {
        SIMD4(Float(pixel[0]), Float(pixel[1]), Float(pixel[2]), Float(pixel[3]))
    }

    /// Black at `alpha` (0…1) over a premultiplied colour.
    @inline(__always)
    static func shadow(_ alpha: Float, over destination: SIMD4<Float>) -> SIMD4<Float> {
        over(SIMD4(0, 0, 0, 255 * alpha), destination)
    }

    /// Premultiplied source-over (0…255 channels).
    @inline(__always)
    static func over(_ source: SIMD4<Float>, _ destination: SIMD4<Float>) -> SIMD4<Float> {
        source + destination * (1 - source.w / 255)
    }
}

/// Approximate Gaussian blur: four box passes with edge extension (vImage, CPU, deterministic).
enum BoxBlur {
    /// `radius` in output pixels (≈ 2 σ).
    @discardableResult
    static func apply(radius: Double, to context: CGContext) -> Bool {
        let sigma = radius / 2
        var kernel = UInt32((3 * sigma * sigma + 1).squareRoot().rounded())
        if kernel % 2 == 0 { kernel += 1 }
        guard kernel >= 3, let data = context.data, context.bitsPerPixel == 32 else { return false }
        let width = vImagePixelCount(context.width)
        let height = vImagePixelCount(context.height)
        var source = vImage_Buffer(data: data, height: height, width: width, rowBytes: context.bytesPerRow)
        let tempRowBytes = context.width * 4
        guard let temp = malloc(tempRowBytes * context.height) else { return false }
        defer { free(temp) }
        var scratch = vImage_Buffer(data: temp, height: height, width: width, rowBytes: tempRowBytes)
        let flags = vImage_Flags(kvImageEdgeExtend)
        for _ in 0..<2 {
            guard
                vImageBoxConvolve_ARGB8888(&source, &scratch, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError,
                vImageBoxConvolve_ARGB8888(&scratch, &source, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError
            else { return false }
        }
        return true
    }
}
