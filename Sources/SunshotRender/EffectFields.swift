import Foundation
import SunshotCore

/// S8: the per-pixel maths of patterns, vignettes and overlay textures. Every function takes canvas coordinates
/// (canvas pixels at 1×, top-left origin), so the result is the same picture at any render scale; `pixel` is the
/// size of one output pixel in canvas units and only sets the anti-aliasing width.
struct EffectGeometry {
    /// Canvas size in canvas units.
    let width: Double
    let height: Double
    /// Output pixels per canvas unit.
    let scaleX: Double
    let scaleY: Double

    init(canvas: PixelSize, pixelWidth: Int, pixelHeight: Int) {
        width = Double(max(canvas.width, 1))
        height = Double(max(canvas.height, 1))
        scaleX = Double(pixelWidth) / width
        scaleY = Double(pixelHeight) / height
    }

    var pixel: Double { 1 / max(scaleX, 1e-9) }
    var longEdge: Double { max(width, height) }

    @inline(__always) func u(_ x: Int) -> Double { (Double(x) + 0.5) / scaleX }
    @inline(__always) func v(_ y: Int) -> Double { (Double(y) + 0.5) / scaleY }
}

@inline(__always) func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Distance from `value` to the nearest multiple of `period`.
@inline(__always) func distanceToLattice(_ value: Double, _ period: Double) -> Double {
    abs(value - period * (value / period).rounded())
}

/// Deterministic hash of an integer lattice point to `0..<1` (independent of the dither noise).
@inline(__always) func latticeHash(_ x: Int, _ y: Int, seed: UInt32) -> Double {
    Double(PixelFill.noise(x &+ Int(seed), y &- Int(seed >> 3)))
}

/// Smooth value noise on a unit lattice.
func valueNoise(_ u: Double, _ v: Double, seed: UInt32) -> Double {
    let fu = u.rounded(.down)
    let fv = v.rounded(.down)
    let ix = Int(fu)
    let iy = Int(fv)
    let tx = smoothstep(0, 1, u - fu)
    let ty = smoothstep(0, 1, v - fv)
    let a = latticeHash(ix, iy, seed: seed)
    let b = latticeHash(ix + 1, iy, seed: seed)
    let c = latticeHash(ix, iy + 1, seed: seed)
    let d = latticeHash(ix + 1, iy + 1, seed: seed)
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
}

/// Coverage (0…1) of a pattern at a canvas point.
struct PatternField {
    /// Spacing of lines, rings and dots in canvas units.
    static let period: Double = 32
    static let rayCount: Double = 24

    let kind: PatternKind
    let thickness: Double
    let centerX: Double
    let centerY: Double
    let pixel: Double

    init(_ pattern: BackdropPattern, geometry: EffectGeometry) {
        kind = pattern.kind
        thickness = pattern.thickness
        centerX = geometry.width / 2
        centerY = geometry.height / 2
        pixel = geometry.pixel
    }

    /// Anti-aliased coverage of a shape whose signed distance (positive inside) is `inside`.
    @inline(__always) private func edge(_ inside: Double) -> Double { min(max(inside / pixel + 0.5, 0), 1) }

    func coverage(u: Double, v: Double) -> Double {
        let period = Self.period
        switch kind {
        case .none:
            return 0
        case .circles:
            let radius = ((u - centerX) * (u - centerX) + (v - centerY) * (v - centerY)).squareRoot()
            return edge(thickness - distanceToLattice(radius, period))
        case .waves:
            let wavelength = 96.0
            let amplitude = 6.0
            let phase = 2 * Double.pi * u / wavelength
            let shifted = v + amplitude * sin(phase)
            let slope = amplitude * 2 * Double.pi / wavelength * cos(phase)
            return edge(thickness - distanceToLattice(shifted, period) / (1 + slope * slope).squareRoot())
        case .dots:
            let dx = distanceToLattice(u - centerX, period)
            let dy = distanceToLattice(v - centerY, period)
            return edge(2.5 * thickness - (dx * dx + dy * dy).squareRoot())
        case .rays:
            let dx = u - centerX
            let dy = v - centerY
            let radius = (dx * dx + dy * dy).squareRoot()
            let sector = 2 * Double.pi / Self.rayCount
            let angle = distanceToLattice(atan2(dy, dx), sector)
            let halfWidth = min(sector * 0.12 * thickness, sector / 2)
            return edge(-radius * sin(angle - halfWidth))
        case .grid:
            let distance = min(distanceToLattice(u - centerX, period), distanceToLattice(v - centerY, period))
            return edge(0.5 * thickness - distance)
        case .stripes:
            let diagonal = (u + v) / 2.0.squareRoot()
            return edge(min(period / 8 * thickness, period / 2) - distanceToLattice(diagonal, period))
        case .noise:
            let value = valueNoise(u / 6, v / 6, seed: 0x5EED)
            let threshold = 0.68 - 0.1 * thickness
            return smoothstep(threshold, threshold + 0.08, value)
        }
    }
}

/// Weight (0…1) of a vignette at a canvas point: 0 in the middle, rising towards the corners.
struct VignetteField {
    let centerX: Double
    let centerY: Double
    let start: Double

    init(_ vignette: Vignette, geometry: EffectGeometry) {
        centerX = geometry.width / 2
        centerY = geometry.height / 2
        start = 1 - vignette.spread * 0.9
    }

    func weight(u: Double, v: Double) -> Double {
        let nx = (u - centerX) / centerX
        let ny = (v - centerY) / centerY
        let distance = ((nx * nx + ny * ny) / 2).squareRoot()
        return smoothstep(start, start + 0.7, distance)
    }
}
