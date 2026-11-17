/// A Sunshot-generated wallpaper: a recipe (base gradient + palette + seed) that the renderer turns into soft
/// colour fields at any resolution. No bitmap artwork is bundled; the recipe *is* the provenance.
public struct Wallpaper: Codable, Hashable, Sendable, Identifiable {
    /// The design is laid out in a 16:10 space (1.6 × 1.0 units) and drawn with "fill" (cover) scaling.
    public static let designWidth = 1.6
    public static let designHeight = 1.0

    public let id: String
    public let name: String
    /// Seed of the deterministic generator that places the colour fields.
    public let seed: UInt64
    public let base: GradientSpec
    public let palette: [RGBAColor]
    public let fieldCount: Int

    public init(id: String, name: String, seed: UInt64, base: GradientSpec, palette: [RGBAColor], fieldCount: Int) {
        self.id = id
        self.name = name
        self.seed = seed
        self.base = base
        self.palette = palette
        self.fieldCount = min(max(fieldCount, 0), 16)
    }

    /// Soft colour fields, generated deterministically from `seed` (same seed → same wallpaper).
    public var fields: [ColorField] {
        guard !palette.isEmpty else { return [] }
        var random = SeededRandom(seed: seed)
        return (0..<fieldCount).map { index in
            ColorField(
                x: random.next(in: -0.1...(Self.designWidth + 0.1)),
                y: random.next(in: -0.1...(Self.designHeight + 0.1)),
                radius: random.next(in: 0.45...0.95),
                strength: random.next(in: 0.55...0.9),
                color: palette[index % palette.count])
        }
    }
}

/// A round field of colour with a smooth falloff to nothing at `radius` (design units).
public struct ColorField: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    public let strength: Double
    public let color: RGBAColor

    /// Weight at distance `d` from the centre: `strength × (1 − (d/r)²)³`, 0 outside.
    public func weight(atDistanceSquared d2: Double) -> Double {
        let q = 1 - d2 / (radius * radius)
        return q > 0 ? strength * q * q * q : 0
    }
}

/// SplitMix64: tiny, fast, deterministic on every platform.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `range`.
    public mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
