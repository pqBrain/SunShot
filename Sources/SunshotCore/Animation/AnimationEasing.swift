import Foundation

/// How a keyframe clip moves from its start state to its target. Every curve maps 0 → 0 and 1 → 1 exactly;
/// all but `spring` are monotonic and stay within 0…1. `spring` is a damped spring that overshoots a little
/// (≈ 4.6 %) and settles within 2 % from 80 % of the clip on.
public enum AnimationEasing: String, Codable, CaseIterable, Hashable, Sendable {
    case spring, linear, cubic, out, inOut, outCirc

    public static let defaultEasing: AnimationEasing = .spring

    /// Damping ratio and natural frequency (per unit of clip time) of `spring`.
    static let springDamping = 0.7
    static let springFrequency = 8.5

    /// Whether the curve never goes backwards (everything except `spring`).
    public var isMonotonic: Bool { self != .spring }

    /// Eased progress for clip progress `rawT` (clamped to 0…1; non-finite → 1).
    public func value(at rawT: Double) -> Double {
        guard rawT.isFinite else { return 1 }
        let t = min(max(rawT, 0), 1)
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        switch self {
        case .linear:
            return t
        case .cubic:
            return TransformAnimation.easeInOut(t)
        case .out:
            let u = 1 - t
            return 1 - u * u * u
        case .inOut:
            return (1 - cos(Double.pi * t)) / 2
        case .outCirc:
            return (1 - (t - 1) * (t - 1)).squareRoot()
        case .spring:
            // Normalised so the curve lands on exactly 1 at t = 1 (the raw spring is 0.3 % short there).
            return Self.rawSpring(t) + (1 - Self.rawSpring(1)) * t
        }
    }

    /// Under-damped spring step response: 1 − e^(−ζωt)(cos ω_d t + ζω/ω_d sin ω_d t).
    static func rawSpring(_ t: Double) -> Double {
        let zeta = springDamping
        let omega = springFrequency
        let damped = omega * (1 - zeta * zeta).squareRoot()
        let envelope = exp(-zeta * omega * t)
        return 1 - envelope * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }
}

extension ContentTransform {
    /// Blend from `self` (progress 0) to `target` (progress 1) that, unlike `interpolated`, also extrapolates a
    /// little past the ends (a spring's overshoot). Progress is clamped to −0.5…1.5; the result stays in range.
    /// The end points are exact.
    public func blended(to target: ContentTransform, progress rawProgress: Double) -> ContentTransform {
        let p = rawProgress.isFinite ? min(max(rawProgress, -0.5), 1.5) : 1
        if p == 1 { return target }
        if p == 0 { return self }
        func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * p }
        var delta = target.rotation - rotation
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return ContentTransform(
            unchecked: Self.clampPosition(lerp(x, target.x)), Self.clampPosition(lerp(y, target.y)),
            min(max(lerp(zoom, target.zoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound),
            Self.normaliseRotation(rotation + delta * p), Self.clampTilt(lerp(tiltX, target.tiltX)),
            Self.clampTilt(lerp(tiltY, target.tiltY)))
    }
}
