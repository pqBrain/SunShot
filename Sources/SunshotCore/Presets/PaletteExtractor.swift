/// S8: extracts a small palette of prominent, distinct colours from an image's pixels (pure and deterministic).
///
/// Pixels are counted in a 5-bit-per-channel histogram (transparent pixels are ignored); the most populated
/// bins are then picked greedily, skipping colours too close to one already picked, with a shrinking distance so
/// low-colour images still fill the palette. If an image has fewer distinct colours than asked for, the rest are
/// tints and shades of what was found.
public enum PaletteExtractor {
    public static let defaultCount = 6
    /// Pixels with alpha below this (0…255) are ignored.
    static let minimumAlpha: UInt8 = 128
    /// Minimum distance between picked colours (sRGB, 0…1 per channel), tried in order.
    static let distances: [Double] = [0.3, 0.2, 0.12, 0.06]

    /// `rgba` holds straight (non-premultiplied) 8-bit RGBA pixels, row by row. Returns exactly `count` colours
    /// ordered by prominence, or an empty array when no pixel is opaque enough.
    public static func extract(rgba: [UInt8], count: Int = defaultCount) -> [RGBAColor] {
        guard count > 0 else { return [] }
        let candidates = histogram(rgba)
        guard !candidates.isEmpty else { return [] }
        var picked: [RGBAColor] = []
        for distance in distances where picked.count < count {
            for candidate in candidates where picked.count < count {
                if picked.allSatisfy({ Self.distance($0, candidate) >= distance }) { picked.append(candidate) }
            }
        }
        return fill(picked, to: count)
    }

    /// Mean colour of each populated bin, most populated first (ties by bin index, so the order is stable).
    private static func histogram(_ rgba: [UInt8]) -> [RGBAColor] {
        var counts = [Int](repeating: 0, count: 32_768)
        var sums = [SIMD3<Double>](repeating: .zero, count: 32_768)
        var index = 0
        while index + 3 < rgba.count {
            if rgba[index + 3] >= minimumAlpha {
                let r = Int(rgba[index])
                let g = Int(rgba[index + 1])
                let b = Int(rgba[index + 2])
                let bin = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
                counts[bin] += 1
                sums[bin] += SIMD3(Double(r), Double(g), Double(b))
            }
            index += 4
        }
        let bins = counts.indices.filter { counts[$0] > 0 }.sorted { lhs, rhs in
            counts[lhs] != counts[rhs] ? counts[lhs] > counts[rhs] : lhs < rhs
        }
        return bins.map { bin in
            let mean = sums[bin] / Double(counts[bin]) / 255
            return RGBAColor(red: mean.x, green: mean.y, blue: mean.z)
        }
    }

    /// Euclidean distance in sRGB with luma-like channel weights (green differences are the most visible).
    static func distance(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Double {
        let dr = lhs.red - rhs.red
        let dg = lhs.green - rhs.green
        let db = lhs.blue - rhs.blue
        return (0.3 * dr * dr + 0.5 * dg * dg + 0.2 * db * db).squareRoot() / 0.7071
    }

    /// Adds tints and shades of the picked colours until there are `count`, skipping near-duplicates.
    private static func fill(_ picked: [RGBAColor], to count: Int) -> [RGBAColor] {
        var result = picked
        let amounts: [Double] = [0.35, 0.6, 0.2, 0.8, 0.5, 0.1]
        outer: for amount in amounts {
            for base in picked {
                for target in [RGBAColor.white, .black] where result.count < count {
                    let candidate = base.mixed(with: target, amount: amount)
                    if result.allSatisfy({ distance($0, candidate) >= 0.04 }) { result.append(candidate) }
                }
                if result.count >= count { break outer }
            }
        }
        // Pathological inputs (pure black or white): grey steps are always distinct.
        var step = 1
        while result.count < count {
            result.append(RGBAColor(red: Double(step) / 8, green: Double(step) / 8, blue: Double(step) / 8))
            step += 1
        }
        return result
    }
}

extension RGBAColor {
    /// Straight-alpha linear mix in sRGB: `amount` 0 = self, 1 = `other`. The result is opaque.
    func mixed(with other: RGBAColor, amount: Double) -> RGBAColor {
        let t = min(max(amount.isFinite ? amount : 0, 0), 1)
        return RGBAColor(
            red: red + (other.red - red) * t, green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t)
    }
}
