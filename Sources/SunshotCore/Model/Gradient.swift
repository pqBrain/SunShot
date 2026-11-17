public enum GradientKind: String, Codable, CaseIterable, Sendable {
    case linear
    case radial
}

public struct GradientStop: Codable, Hashable, Sendable {
    /// Position along the gradient, clamped to `0...1`.
    public var position: Double {
        didSet { position = Self.clamp(position) }
    }
    public var color: RGBAColor

    public init(position: Double, color: RGBAColor) {
        self.position = Self.clamp(position)
        self.color = color
    }

    /// Decoded positions are clamped too (a hand-edited document can't put a stop outside the bar).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            position: try container.decode(Double.self, forKey: .position),
            color: try container.decode(RGBAColor.self, forKey: .color))
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// A linear or radial gradient with 2…12 stops, always sorted by position (stable: equal positions keep their
/// order, which is how a hard edge is made). Colours are interpolated with premultiplied alpha.
///
/// Angle convention (linear): 0° runs bottom→top and angles turn clockwise, so 90° runs left→right.
/// Radial gradients are circles centred on the canvas reaching the farthest corner; they ignore the angle.
public struct GradientSpec: Codable, Hashable, Sendable {
    public static let stopCount: ClosedRange<Int> = 2...12
    /// Arrow-key step for a focused stop, and the ⇧-arrow step.
    public static let keyboardStep = 0.01
    public static let largeKeyboardStep = 0.1

    public var kind: GradientKind
    /// Degrees in `0...360`; anything outside is wrapped (−90 → 270, 450 → 90).
    public var angle: Double {
        didSet { angle = Self.normalizedAngle(angle) }
    }
    public private(set) var stops: [GradientStop]

    public init(kind: GradientKind = .linear, angle: Double = 180, stops: [GradientStop]) {
        self.kind = kind
        self.angle = Self.normalizedAngle(angle)
        self.stops = Self.normalized(stops)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(GradientKind.self, forKey: .kind),
            angle: try container.decode(Double.self, forKey: .angle),
            stops: try container.decode([GradientStop].self, forKey: .stops))
    }

    public static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        if (0...360).contains(value) { return value }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Clamps positions, sorts stably and keeps the count within `stopCount`.
    static func normalized(_ input: [GradientStop]) -> [GradientStop] {
        var stops = input.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map(\.element)
        if stops.count > stopCount.upperBound { stops = Array(stops.prefix(stopCount.upperBound)) }
        if stops.isEmpty {
            stops = [GradientStop(position: 0, color: .black), GradientStop(position: 1, color: .white)]
        }
        if stops.count == 1 {
            stops = [
                GradientStop(position: 0, color: stops[0].color), GradientStop(position: 1, color: stops[0].color),
            ]
        }
        return stops
    }

    public var isOpaque: Bool { stops.allSatisfy { $0.color.alpha >= 1 } }
    public var canAddStop: Bool { stops.count < Self.stopCount.upperBound }
    public var canDeleteStop: Bool { stops.count > Self.stopCount.lowerBound }

    /// Colour at `position` (clamped). Equal stop positions make a hard edge: below it the first, at or above it
    /// the last of them.
    public func color(at position: Double) -> RGBAColor {
        let t = GradientStop.clamp(position)
        guard let first = stops.first, let last = stops.last else { return .clear }
        if t < first.position { return first.color }
        if t >= last.position { return last.color }
        var index = 0
        while index + 2 < stops.count, stops[index + 1].position <= t { index += 1 }
        let lower = stops[index]
        let upper = stops[index + 1]
        let span = upper.position - lower.position
        guard span > 0 else { return upper.color }
        return lower.color.interpolated(to: upper.color, fraction: (t - lower.position) / span)
    }

    /// Adds a stop at `position` coloured as the gradient is there. Returns its index, or nil at 12 stops.
    @discardableResult
    public mutating func addStop(at position: Double) -> Int? {
        guard canAddStop else { return nil }
        let stop = GradientStop(position: position, color: color(at: position))
        let index = stops.firstIndex { $0.position > stop.position } ?? stops.count
        stops.insert(stop, at: index)
        return index
    }

    /// Moves a stop, keeping the list sorted. Returns the stop's new index.
    @discardableResult
    public mutating func moveStop(_ index: Int, to position: Double) -> Int {
        guard stops.indices.contains(index) else { return index }
        var stop = stops[index]
        let old = stop.position
        stop.position = position
        guard stop.position != old else { return index }
        stops.remove(at: index)
        let target: Int
        if stop.position < old {
            target = stops.firstIndex { $0.position >= stop.position } ?? stops.count
        } else {
            target = (stops.lastIndex { $0.position <= stop.position }).map { $0 + 1 } ?? 0
        }
        stops.insert(stop, at: target)
        return target
    }

    public mutating func setStopColor(_ index: Int, _ color: RGBAColor) {
        guard stops.indices.contains(index) else { return }
        stops[index].color = color
    }

    /// Removes a stop. Refused (false) when only 2 remain.
    @discardableResult
    public mutating func deleteStop(_ index: Int) -> Bool {
        guard canDeleteStop, stops.indices.contains(index) else { return false }
        stops.remove(at: index)
        return true
    }

    /// Midpoint of the widest gap between neighbouring stops (where the "+" button adds one).
    public var widestGapMidpoint: Double {
        let gaps = zip(stops, stops.dropFirst()).map { ($1.position - $0.position, ($0.position + $1.position) / 2) }
        return gaps.max { $0.0 < $1.0 }?.1 ?? 0.5
    }
}

extension RGBAColor {
    /// Interpolates with premultiplied alpha (no dark fringe when fading to transparent).
    public func interpolated(to other: RGBAColor, fraction: Double) -> RGBAColor {
        let f = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        let alpha = mix(alpha, other.alpha)
        guard alpha > 0 else {
            return RGBAColor(
                red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue), alpha: 0)
        }
        return RGBAColor(
            red: mix(red * self.alpha, other.red * other.alpha) / alpha,
            green: mix(green * self.alpha, other.green * other.alpha) / alpha,
            blue: mix(blue * self.alpha, other.blue * other.alpha) / alpha,
            alpha: alpha)
    }
}
