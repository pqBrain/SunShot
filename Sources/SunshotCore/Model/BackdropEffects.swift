/// S8: effects drawn with the backdrop. All lengths are canvas pixels at 1× (the render scale multiplies them),
/// so an effect looks the same at every export size. The defaults change nothing, so documents without effects
/// render exactly as before. Every value is clamped to its range, and decoding tolerates missing keys.
public struct BackdropEffects: Codable, Hashable, Sendable {
    public var adjustments: BackdropAdjustments
    public var pattern: BackdropPattern
    public var vignette: Vignette
    public var overlay: OverlayTexture

    public init(
        adjustments: BackdropAdjustments = BackdropAdjustments(), pattern: BackdropPattern = BackdropPattern(),
        vignette: Vignette = Vignette(), overlay: OverlayTexture = OverlayTexture()
    ) {
        self.adjustments = adjustments
        self.pattern = pattern
        self.vignette = vignette
        self.overlay = overlay
    }

    /// Nothing is drawn below the content (adjustments, pattern, vignette and an underlay are all off).
    public var isIdentityBelowContent: Bool {
        adjustments.isIdentity && pattern.isIdentity && vignette.isIdentity
            && (overlay.isIdentity || overlay.position == .above)
    }

    /// An overlay texture is drawn over the content.
    public var drawsAboveContent: Bool { !overlay.isIdentity && overlay.position == .above }

    /// No effect changes any pixel.
    public var isIdentity: Bool { isIdentityBelowContent && !drawsAboveContent }

    private enum CodingKeys: String, CodingKey { case adjustments, pattern, vignette, overlay }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adjustments = try container.decodeIfPresent(BackdropAdjustments.self, forKey: .adjustments) ?? .init()
        pattern = try container.decodeIfPresent(BackdropPattern.self, forKey: .pattern) ?? .init()
        vignette = try container.decodeIfPresent(Vignette.self, forKey: .vignette) ?? .init()
        overlay = try container.decodeIfPresent(OverlayTexture.self, forKey: .overlay) ?? .init()
    }
}

/// Blur, film grain, saturation and opacity of the backdrop (never the content).
public struct BackdropAdjustments: Codable, Hashable, Sendable {
    public static let blurRange: ClosedRange<Double> = 0...50
    public static let noiseRange: ClosedRange<Double> = 0...1
    public static let saturationRange: ClosedRange<Double> = 0...2
    public static let opacityRange: ClosedRange<Double> = 0...1

    /// Blur radius in canvas pixels at 1×.
    public var blur: Double { didSet { blur = Self.blurRange.effectClamp(blur, fallback: 0) } }
    /// Film-grain amount, 0…1.
    public var noise: Double { didSet { noise = Self.noiseRange.effectClamp(noise, fallback: 0) } }
    /// 0 = grey, 1 = unchanged, 2 = twice the chroma.
    public var saturation: Double {
        didSet { saturation = Self.saturationRange.effectClamp(saturation, fallback: 1) }
    }
    /// Backdrop alpha multiplier, 0…1.
    public var opacity: Double { didSet { opacity = Self.opacityRange.effectClamp(opacity, fallback: 1) } }

    public init(blur: Double = 0, noise: Double = 0, saturation: Double = 1, opacity: Double = 1) {
        self.blur = Self.blurRange.effectClamp(blur, fallback: 0)
        self.noise = Self.noiseRange.effectClamp(noise, fallback: 0)
        self.saturation = Self.saturationRange.effectClamp(saturation, fallback: 1)
        self.opacity = Self.opacityRange.effectClamp(opacity, fallback: 1)
    }

    public var isIdentity: Bool { blur == 0 && noise == 0 && saturation == 1 && opacity == 1 }

    private enum CodingKeys: String, CodingKey { case blur, noise, saturation, opacity }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            blur: try container.decodeIfPresent(Double.self, forKey: .blur) ?? 0,
            noise: try container.decodeIfPresent(Double.self, forKey: .noise) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1)
    }
}

/// Sunshot's procedurally generated light-and-shadow textures (no bitmaps ship).
public enum OverlayKind: String, Codable, CaseIterable, Sendable {
    case none, blinds, window, leaves, lattice, ripples, dapple
}

/// Where an overlay texture is drawn: over everything, or over the backdrop only.
public enum OverlayPosition: String, Codable, CaseIterable, Sendable {
    case above, below
}

public struct OverlayTexture: Codable, Hashable, Sendable {
    public static let opacityRange: ClosedRange<Double> = 0...1
    public static let defaultOpacity = 0.3

    public var kind: OverlayKind
    public var opacity: Double {
        didSet { opacity = Self.opacityRange.effectClamp(opacity, fallback: Self.defaultOpacity) }
    }
    public var position: OverlayPosition

    public init(kind: OverlayKind = .none, opacity: Double = defaultOpacity, position: OverlayPosition = .above) {
        self.kind = kind
        self.opacity = Self.opacityRange.effectClamp(opacity, fallback: Self.defaultOpacity)
        self.position = position
    }

    public var isIdentity: Bool { kind == .none || opacity == 0 }

    private enum CodingKeys: String, CodingKey { case kind, opacity, position }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: (try? container.decodeIfPresent(OverlayKind.self, forKey: .kind)) ?? OverlayKind.none,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? Self.defaultOpacity,
            position: (try? container.decodeIfPresent(OverlayPosition.self, forKey: .position)) ?? .above)
    }
}

extension ClosedRange where Bound == Double {
    /// `value` clamped to the range; `fallback` for NaN / infinity.
    func effectClamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
