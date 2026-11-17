/// Where and how the content sits on the canvas: offset, zoom, 2D rotation and 3D tilt.
///
/// - `x`, `y`: offset of the content centre from its laid-out centre, in canvas-width / canvas-height units
///   (−0.5…0.5; ±0.5 puts the centre on the canvas edge).
/// - `zoom`: whole percent, 25…400. Scales the content about its own centre; never changes the canvas size.
/// - `rotation`: degrees, normalised into −180…180 (270 → −90).
/// - `tiltX`, `tiltY`: degrees, −60…60. Positive `tiltX` leans the top edge away from the viewer, positive
///   `tiltY` leans the right edge away. Perspective distance is `perspectiveFactor` × the content's longer side.
///
/// Every value is sanitised on assignment (non-finite values fall back to identity), so a stored transform is
/// always in range. The identity transform leaves the render byte-identical to an untransformed one.
public struct ContentTransform: Hashable, Sendable {
    public static let positionRange: ClosedRange<Double> = -0.5...0.5
    public static let zoomRange: ClosedRange<Double> = 25...400
    public static let rotationRange: ClosedRange<Double> = -180...180
    public static let tiltRange: ClosedRange<Double> = -60...60
    /// Perspective (camera) distance as a multiple of the displayed content's longer side.
    public static let perspectiveFactor: Double = 4

    public static let identity = ContentTransform()

    public var x: Double { didSet { x = Self.clampPosition(x) } }
    public var y: Double { didSet { y = Self.clampPosition(y) } }
    public var zoom: Double { didSet { zoom = Self.clampZoom(zoom) } }
    public var rotation: Double { didSet { rotation = Self.normaliseRotation(rotation) } }
    public var tiltX: Double { didSet { tiltX = Self.clampTilt(tiltX) } }
    public var tiltY: Double { didSet { tiltY = Self.clampTilt(tiltY) } }

    public init(
        x: Double = 0, y: Double = 0, zoom: Double = 100, rotation: Double = 0, tiltX: Double = 0, tiltY: Double = 0
    ) {
        self.x = Self.clampPosition(x)
        self.y = Self.clampPosition(y)
        self.zoom = Self.clampZoom(zoom)
        self.rotation = Self.normaliseRotation(rotation)
        self.tiltX = Self.clampTilt(tiltX)
        self.tiltY = Self.clampTilt(tiltY)
    }

    public var isIdentity: Bool { self == .identity }
    /// True when the content is drawn flat (no perspective).
    public var isFlat: Bool { tiltX == 0 && tiltY == 0 }
    /// Zoom as a factor (1 = 100 %).
    public var scale: Double { zoom / 100 }

    // MARK: Sanitising

    public static func clampPosition(_ value: Double) -> Double { clamp(value, to: positionRange, fallback: 0) }

    /// Whole percent within 25…400 (150.4 → 150, 24 → 25).
    public static func clampZoom(_ value: Double) -> Double {
        clamp(value.rounded(), to: zoomRange, fallback: 100)
    }

    /// Into −180…180: 270 → −90, −190 → 170, 540 → 180. Non-finite → 0.
    public static func normaliseRotation(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        guard !rotationRange.contains(value) else { return value + 0 }  // + 0 turns −0 into 0
        var wrapped = value.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped < -180 { wrapped += 360 }
        return wrapped + 0
    }

    public static func clampTilt(_ value: Double) -> Double { clamp(value, to: tiltRange, fallback: 0) }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound) + 0
    }

    // MARK: Animation

    /// Linear blend from `self` (t = 0) to `target` (t = 1). Rotation takes the short way round; t is clamped.
    /// Zoom is not rounded mid-way so animations are smooth; the end points are exact.
    public func interpolated(to target: ContentTransform, t rawT: Double) -> ContentTransform {
        let t = rawT.isFinite ? min(max(rawT, 0), 1) : 1
        if t >= 1 { return target }
        if t <= 0 { return self }
        func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * t }
        var delta = target.rotation - rotation
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        // Built without whole-percent zoom rounding so animation frames ease continuously; values stay in range.
        return ContentTransform(
            unchecked: Self.clampPosition(lerp(x, target.x)), Self.clampPosition(lerp(y, target.y)),
            min(max(lerp(zoom, target.zoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound),
            Self.normaliseRotation(rotation + delta * t), Self.clampTilt(lerp(tiltX, target.tiltX)),
            Self.clampTilt(lerp(tiltY, target.tiltY)))
    }

    private init(unchecked x: Double, _ y: Double, _ zoom: Double, _ rotation: Double, _ tiltX: Double, _ tiltY: Double)
    {
        self.x = x
        self.y = y
        self.zoom = zoom
        self.rotation = rotation
        self.tiltX = tiltX
        self.tiltY = tiltY
    }
}

extension ContentTransform: Codable {
    private enum CodingKeys: String, CodingKey { case x, y, zoom, rotation, tiltX, tiltY }

    /// Tolerant: missing or invalid values become their identity value, out-of-range values are clamped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, _ fallback: Double) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init(
            x: value(.x, 0), y: value(.y, 0), zoom: value(.zoom, 100), rotation: value(.rotation, 0),
            tiltX: value(.tiltX, 0), tiltY: value(.tiltY, 0))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(zoom, forKey: .zoom)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(tiltX, forKey: .tiltX)
        try container.encode(tiltY, forKey: .tiltY)
    }
}

/// The content transform plus which layout preset (if any) produced it. Kept in the document as style, so it
/// survives clearing and re-importing content, and undo restores the preset selection too.
public struct ContentPlacement: Hashable, Sendable {
    public var transform: ContentTransform
    /// Id of the applied layout preset; cleared by any manual change.
    public var layoutPresetID: String?

    public init(transform: ContentTransform = .identity, layoutPresetID: String? = nil) {
        self.transform = transform
        self.layoutPresetID = layoutPresetID
    }
}

extension ContentPlacement: Codable {
    private enum CodingKeys: String, CodingKey { case transform, layoutPresetID }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transform = ((try? container.decodeIfPresent(ContentTransform.self, forKey: .transform)) ?? nil) ?? .identity
        layoutPresetID = (try? container.decodeIfPresent(String.self, forKey: .layoutPresetID)) ?? nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transform, forKey: .transform)
        try container.encodeIfPresent(layoutPresetID, forKey: .layoutPresetID)
    }
}
