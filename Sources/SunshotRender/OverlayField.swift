import Foundation
import SunshotCore

/// S8: Sunshot's procedural light-and-shadow textures. `shade(u:v:)` returns how much shadow (0…1) falls on a
/// canvas point. Textures are laid out relative to the canvas (not in pixels), so they look the same at every
/// size and never tile.
struct OverlayField {
    /// A soft ellipse in long-edge-normalised units.
    private struct Blob {
        let x: Double
        let y: Double
        let cosine: Double
        let sine: Double
        let length: Double
        let width: Double
    }

    let kind: OverlayKind
    private let width: Double
    private let height: Double
    private let longEdge: Double
    private let blobs: [Blob]

    init(_ kind: OverlayKind, geometry: EffectGeometry) {
        self.kind = kind
        width = geometry.width
        height = geometry.height
        longEdge = geometry.longEdge
        switch kind {
        case .leaves:
            blobs = Self.blobs(
                count: 18, seed: 0x1EAF, length: 0.07...0.15, width: 0.025...0.05, aspect: width / longEdge,
                tall: height / longEdge)
        case .dapple:
            blobs = Self.blobs(
                count: 24, seed: 0xDA99, length: 0.025...0.07, width: 0.02...0.06, aspect: width / longEdge,
                tall: height / longEdge)
        default:
            blobs = []
        }
    }

    private static func blobs(
        count: Int, seed: UInt64, length: ClosedRange<Double>, width: ClosedRange<Double>, aspect: Double,
        tall: Double
    ) -> [Blob] {
        var random = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            let angle = random.next(in: 0...Double.pi)
            let long = random.next(in: length)
            return Blob(
                x: random.next(in: -0.05...(aspect + 0.05)), y: random.next(in: -0.05...(tall + 0.05)),
                cosine: cos(angle), sine: sin(angle), length: long, width: min(random.next(in: width), long))
        }
    }

    /// Strongest coverage of any blob at a long-edge-normalised point.
    private func blobCoverage(_ nu: Double, _ nv: Double) -> Double {
        var strongest = 0.0
        for blob in blobs {
            let dx = nu - blob.x
            let dy = nv - blob.y
            guard abs(dx) < blob.length, abs(dy) < blob.length else { continue }
            let along = (dx * blob.cosine + dy * blob.sine) / blob.length
            let across = (-dx * blob.sine + dy * blob.cosine) / blob.width
            let q = along * along + across * across
            strongest = max(strongest, 1 - smoothstep(0.45, 1, q))
        }
        return strongest
    }

    @inline(__always) private func softBand(_ x: Double, _ low: Double, _ high: Double, _ soft: Double) -> Double {
        smoothstep(low - soft, low + soft, x) * (1 - smoothstep(high - soft, high + soft, x))
    }

    func shade(u: Double, v: Double) -> Double {
        let nu = u / longEdge
        let nv = v / longEdge
        switch kind {
        case .none:
            return 0
        case .blinds:
            let t = (nu * 0.31 + nv * 0.95) * 9
            let f = t - t.rounded(.down)
            return softBand(f, 0.3, 0.72, 0.07)
        case .window:
            let a = u / width
            let b = v / height
            let x = a - 0.25 * (b - 0.5)
            let lit = softBand(x, 0.14, 0.86, 0.03) * softBand(b, 0.1, 0.8, 0.03)
            let mullions = max(softBand(x, 0.485, 0.515, 0.012), softBand(b, 0.435, 0.465, 0.012))
            return 1 - lit * (1 - mullions)
        case .leaves:
            return blobCoverage(nu, nv)
        case .lattice:
            let first = (nu + nv) * 7
            let second = (nu - nv) * 7
            let barA = 1 - smoothstep(0.03, 0.13, abs(first - first.rounded()))
            let barB = 1 - smoothstep(0.03, 0.13, abs(second - second.rounded()))
            return max(barA, barB)
        case .ripples:
            let wave = sin(nu * 28 + 1.7 * sin(nv * 19)) + sin(nv * 23 + 1.3 * sin(nu * 17))
            return smoothstep(0.4, 1.6, wave)
        case .dapple:
            return 0.8 * (1 - blobCoverage(nu, nv))
        }
    }
}
