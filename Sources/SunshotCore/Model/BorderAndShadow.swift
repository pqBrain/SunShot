import Foundation

/// How the content's corners are drawn.
public enum CornerStyle: String, Codable, CaseIterable, Sendable {
    /// Square corners; the radius is ignored.
    case sharp
    /// Continuous ("squircle-style") corners.
    case smooth
    /// Circular-arc corners.
    case round
}

public struct Border: Codable, Hashable, Sendable {
    public static let radiusRange: ClosedRange<Double> = 0...200

    public var style: CornerStyle
    /// Corner radius in content pixels at 1×, clamped to `radiusRange`.
    public var radius: Double {
        didSet { radius = Self.clamp(radius) }
    }

    public init(style: CornerStyle = SunshotDefaults.cornerStyle, radius: Double = SunshotDefaults.cornerRadius) {
        self.style = style
        self.radius = Self.clamp(radius)
    }

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return SunshotDefaults.cornerRadius }
        return min(max(value, radiusRange.lowerBound), radiusRange.upperBound)
    }

    /// Parses a typed radius ("80", " 80.5 px"). Returns nil for non-numeric text.
    public static func parseRadius(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("px") { trimmed = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return clamp(value)
    }
}

public enum ShadowStyle: String, Codable, CaseIterable, Sendable {
    case none
    /// Large, soft shadow.
    case spread
    /// Tight shadow that stays close to the content edge.
    case hug
}

public enum ShadowIntensity: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// A direction and strength in the unit circle (x right, y down). Length is clamped to ≤ 1.
public struct UnitOffset: Codable, Hashable, Sendable {
    public private(set) var x: Double
    public private(set) var y: Double

    public init(x: Double, y: Double) {
        let safeX = x.isFinite ? x : 0
        let safeY = y.isFinite ? y : 0
        let length = (safeX * safeX + safeY * safeY).squareRoot()
        let scale = length > 1 ? 1 / length : 1
        self.x = safeX * scale
        self.y = safeY * scale
    }

    public static let zero = UnitOffset(x: 0, y: 0)
    /// Arrow-key step for the light-source handle, and the ⇧-arrow step.
    public static let keyboardStep = 0.02
    public static let largeKeyboardStep = 0.1

    /// Moves by (dx, dy), staying inside the unit circle.
    public func nudged(dx: Double, dy: Double) -> UnitOffset { UnitOffset(x: x + dx, y: y + dy) }
}

public struct Shadow: Codable, Hashable, Sendable {
    public var style: ShadowStyle
    public var intensity: ShadowIntensity
    /// Direction the shadow falls (x right, y down). The light-source handle sits at the opposite point.
    public var offset: UnitOffset

    public init(
        style: ShadowStyle = SunshotDefaults.shadowStyle,
        intensity: ShadowIntensity = SunshotDefaults.shadowIntensity,
        offset: UnitOffset = SunshotDefaults.shadowOffset
    ) {
        self.style = style
        self.intensity = intensity
        self.offset = offset
    }

    /// Light-source handle position (unit circle, x right, y down): opposite to where the shadow falls.
    public var lightPosition: UnitOffset { UnitOffset(x: -offset.x, y: -offset.y) }

    /// Sets the shadow from a light-source handle position.
    public mutating func setLight(at position: UnitOffset) {
        offset = UnitOffset(x: -position.x, y: -position.y)
    }
}
