/// S8: repeating line/dot patterns drawn over the backdrop.
public enum PatternKind: String, Codable, CaseIterable, Sendable {
    case none, circles, waves, dots, rays, grid, stripes, noise
}

public struct BackdropPattern: Codable, Hashable, Sendable {
    public static let intensityRange: ClosedRange<Double> = 0...1
    public static let thicknessRange: ClosedRange<Double> = 0.25...3
    public static let defaultIntensity = 0.2
    public static let defaultColor = RGBAColor(rgb: 0x23232B)

    public var kind: PatternKind
    /// How strongly the pattern colour covers the backdrop, 0…1.
    public var intensity: Double {
        didSet { intensity = Self.intensityRange.effectClamp(intensity, fallback: Self.defaultIntensity) }
    }
    /// Line / dot size multiplier, 0.25…3 (1 = Sunshot's default weight).
    public var thickness: Double {
        didSet { thickness = Self.thicknessRange.effectClamp(thickness, fallback: 1) }
    }
    public var color: RGBAColor

    public init(
        kind: PatternKind = .none, intensity: Double = defaultIntensity, thickness: Double = 1,
        color: RGBAColor = defaultColor
    ) {
        self.kind = kind
        self.intensity = Self.intensityRange.effectClamp(intensity, fallback: Self.defaultIntensity)
        self.thickness = Self.thicknessRange.effectClamp(thickness, fallback: 1)
        self.color = color
    }

    public var isIdentity: Bool { kind == .none || intensity == 0 || color.alpha == 0 }

    private enum CodingKeys: String, CodingKey { case kind, intensity, thickness, color }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: (try? container.decodeIfPresent(PatternKind.self, forKey: .kind)) ?? PatternKind.none,
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? Self.defaultIntensity,
            thickness: try container.decodeIfPresent(Double.self, forKey: .thickness) ?? 1,
            color: try container.decodeIfPresent(RGBAColor.self, forKey: .color) ?? Self.defaultColor)
    }
}

/// Darkens or lightens the backdrop towards the canvas edges.
public enum VignetteStyle: String, Codable, CaseIterable, Sendable {
    case none, dark, light
}

public struct Vignette: Codable, Hashable, Sendable {
    public static let range: ClosedRange<Double> = 0...1

    public var style: VignetteStyle
    /// How far from the edges towards the centre it reaches, 0…1.
    public var spread: Double { didSet { spread = Self.range.effectClamp(spread, fallback: 0.5) } }
    /// Strength at the corners, 0…1.
    public var intensity: Double { didSet { intensity = Self.range.effectClamp(intensity, fallback: 0.5) } }

    public init(style: VignetteStyle = .none, spread: Double = 0.5, intensity: Double = 0.5) {
        self.style = style
        self.spread = Self.range.effectClamp(spread, fallback: 0.5)
        self.intensity = Self.range.effectClamp(intensity, fallback: 0.5)
    }

    public var isIdentity: Bool { style == .none || intensity == 0 }

    private enum CodingKeys: String, CodingKey { case style, spread, intensity }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            style: (try? container.decodeIfPresent(VignetteStyle.self, forKey: .style)) ?? VignetteStyle.none,
            spread: try container.decodeIfPresent(Double.self, forKey: .spread) ?? 0.5,
            intensity: try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.5)
    }
}
