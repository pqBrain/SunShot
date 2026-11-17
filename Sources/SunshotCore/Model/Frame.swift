import Foundation

/// The window or card drawn around the content. All frames are vector-drawn by Sunshot.
public enum FrameKind: String, Codable, CaseIterable, Sendable {
    case none, macWindow, browserWindow, card, stack, stack2, thickBorder, winWindow

    /// Frames with a title bar or toolbar that shows the frame title.
    public var hasTitle: Bool {
        switch self {
        case .macWindow, .browserWindow, .winWindow: true
        case .none, .card, .stack, .stack2, .thickBorder: false
        }
    }

    /// Tolerant decoding: an unknown kind (from a newer version) falls back to `none`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FrameKind(rawValue: raw) ?? .none
    }
}

/// Chrome sizes at UI scale 100 %, in content pixels at 1×.
public enum FrameMetrics {
    public static let macBarHeight: Double = 28
    public static let browserBarHeight: Double = 44
    public static let winBarHeight: Double = 32
    public static let cardPadding: Double = 24
    public static let thickBorderWidth: Double = 14
    /// Each card behind a stack sits this much higher than the one in front of it.
    public static let stackOffset: Double = 12
    /// Scale and opacity of the cards behind a stack, nearest first.
    public static let stackScales: [Double] = [0.96, 0.92]
    public static let stackOpacities: [Double] = [0.7, 0.45]
    /// Traffic-light circles: diameter, gap between circles, inset from the left edge.
    public static let trafficLightDiameter: Double = 12
    public static let trafficLightGap: Double = 8
    public static let trafficLightInset: Double = 12
    /// Title font size in the mac and Windows bars, and in the browser address field.
    public static let titleFontSize: Double = 13
    public static let addressFontSize: Double = 12
}

/// The frame around the content: kind, title and chrome scale.
public struct Frame: Codable, Hashable, Sendable {
    public static let maxTitleLength = 120
    public static let uiScaleRange: ClosedRange<Double> = 50...200

    public var kind: FrameKind
    /// Title shown in the chrome. Newlines become spaces; cut to `maxTitleLength` characters.
    public var title: String {
        didSet { if title != Self.sanitizeTitle(title) { title = Self.sanitizeTitle(title) } }
    }
    /// Chrome scale in percent (50…200, whole numbers). Content is never scaled by it.
    public var uiScale: Double {
        didSet { if uiScale != Self.clampScale(uiScale) { uiScale = Self.clampScale(uiScale) } }
    }

    public init(
        kind: FrameKind = SunshotDefaults.frameKind, title: String = "", uiScale: Double = SunshotDefaults.frameUIScale
    ) {
        self.kind = kind
        self.title = Self.sanitizeTitle(title)
        self.uiScale = Self.clampScale(uiScale)
    }

    private enum CodingKeys: String, CodingKey { case kind, title, uiScale }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decodeIfPresent(FrameKind.self, forKey: .kind) ?? SunshotDefaults.frameKind,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            uiScale: try container.decodeIfPresent(Double.self, forKey: .uiScale) ?? SunshotDefaults.frameUIScale)
    }

    /// UI scale as a factor (1 = 100 %).
    public var scaleFactor: Double { uiScale / 100 }

    /// The title as drawn: empty when it is only whitespace.
    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : title
    }

    /// Replaces line breaks with spaces and keeps at most `maxTitleLength` characters (emoji-safe).
    public static func sanitizeTitle(_ text: String) -> String {
        let singleLine = String(text.map { $0.isNewline ? " " : $0 })
        return String(singleLine.prefix(maxTitleLength))
    }

    /// Rounds to a whole percent and clamps to `uiScaleRange`; non-finite values become the default.
    public static func clampScale(_ value: Double) -> Double {
        guard value.isFinite else { return SunshotDefaults.frameUIScale }
        return min(max(value.rounded(), uiScaleRange.lowerBound), uiScaleRange.upperBound)
    }
}
