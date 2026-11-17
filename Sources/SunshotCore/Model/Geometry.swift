/// Integer pixel dimensions. Always at least 1×1.
public struct PixelSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var aspectRatio: Double { Double(width) / Double(height) }

    /// Decoded through `init(width:height:)`, so a file can't smuggle in a zero or negative side.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.decode(Int.self, forKey: .width),
            height: try container.decode(Int.self, forKey: .height))
    }
}

extension Int {
    /// Largest length layout and export maths produce. Far beyond `SunshotDefaults.maxCanvasSide` (export is
    /// refused above that), yet small enough that products and sums of lengths never overflow.
    public static let maxLayoutLength = 1 << 24

    /// `value` rounded and clamped to `0...maxLayoutLength`; NaN gives 0. Never traps, unlike `Int(_:)`.
    public init(saturatingLength value: Double) {
        guard !value.isNaN else {
            self = 0
            return
        }
        self = Int(Swift.min(Swift.max(value.rounded(), 0), Double(Int.maxLayoutLength)))
    }
}

/// A rectangle in canvas points, origin at the top-left.
public struct LayoutRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}
