import Foundation

/// The tools of Annotate mode, in palette order.
public enum AnnotationTool: String, CaseIterable, Codable, Sendable {
    case select, pen, highlighter, eraser, arrow, rectangle, text, step, redact, sticker

    /// Single-key shortcut in Annotate mode (the sticker picker uses ⌥⌘S instead).
    public var shortcut: Character? {
        switch self {
        case .select: "v"
        case .pen: "p"
        case .highlighter: "h"
        case .eraser: "e"
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .step: "s"
        case .redact: "b"
        case .sticker: nil
        }
    }

    /// The tool for a typed key, case-insensitive.
    public static func forShortcut(_ key: Character) -> AnnotationTool? {
        let lower = Character(key.lowercased())
        return allCases.first { $0.shortcut == lower }
    }

    /// The annotation kind a drawing tool creates (nil for select and eraser).
    public var kind: AnnotationKind? {
        switch self {
        case .select, .eraser: nil
        case .pen: .pen
        case .highlighter: .highlighter
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .text: .text
        case .step: .step
        case .redact: .redact
        case .sticker: .sticker
        }
    }
}

/// S / M / L. Widths are content pixels for content up to 1000 px on its long edge, and grow with larger content
/// so a stroke looks the same on a retina screenshot.
public enum AnnotationSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    public var baseWidth: Double {
        switch self {
        case .small: 3
        case .medium: 6
        case .large: 12
        }
    }

    public func lineWidth(contentLongEdge: Double) -> Double {
        let factor = contentLongEdge.isFinite ? max(1, contentLongEdge / 1000) : 1
        return baseWidth * factor
    }

    /// `[` / `]`: one step smaller / larger, stopping at the ends.
    public func stepped(by delta: Int) -> AnnotationSize {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 1
        return all[min(max(index + delta, 0), all.count - 1)]
    }
}

/// How step counters are labelled.
public enum StepFormat: String, CaseIterable, Codable, Sendable {
    case numbers, letters

    /// Label of the step at zero-based `index`: 1, 2, 3… or A…Z, AA, AB…
    public func label(_ index: Int) -> String {
        switch self {
        case .numbers:
            return String(index + 1)
        case .letters:
            var value = index
            var result = ""
            repeat {
                let scalar = UnicodeScalar(UInt8(65 + value % 26))
                result = String(Character(scalar)) + result
                value = value / 26 - 1
            } while value >= 0
            return result
        }
    }
}

/// The current drawing settings (editor state, not part of the document).
public struct AnnotationStyle: Hashable, Sendable {
    public var color: RGBAColor
    public var size: AnnotationSize
    public var lineStyle: AnnotationLineStyle
    public var filled: Bool
    public var redaction: RedactionMode
    public var alignment: AnnotationTextAlignment
    public var sticker: String

    public init(
        color: RGBAColor = AnnotationDefaults.color, size: AnnotationSize = .medium,
        lineStyle: AnnotationLineStyle = .solid, filled: Bool = false, redaction: RedactionMode = .pixelate,
        alignment: AnnotationTextAlignment = .left, sticker: String = AnnotationDefaults.stickers[0]
    ) {
        self.color = color
        self.size = size
        self.lineStyle = lineStyle
        self.filled = filled
        self.redaction = redaction
        self.alignment = alignment
        self.sticker = sticker
    }

    /// Size-derived measures for content with `longEdge` pixels on its long side.
    public func lineWidth(for kind: AnnotationKind, longEdge: Double) -> Double {
        let width = size.lineWidth(contentLongEdge: longEdge)
        return kind == .highlighter ? width * AnnotationDefaults.highlighterWidthFactor : width
    }

    public func fontSize(longEdge: Double) -> Double { size.lineWidth(contentLongEdge: longEdge) * 4 }
    public func stepDiameter(longEdge: Double) -> Double { size.lineWidth(contentLongEdge: longEdge) * 6 + 12 }
    public func stickerSize(longEdge: Double) -> Double { size.lineWidth(contentLongEdge: longEdge) * 12 }
}

/// A named palette colour (the name is the VoiceOver label).
public struct AnnotationColor: Hashable, Sendable {
    public let name: String
    public let color: RGBAColor
}

/// Sunshot's annotation defaults and palette.
public enum AnnotationDefaults {
    public static let color = RGBAColor(rgb: 0xF2453D)
    /// Highlighter strokes are this many times the pen width, at `highlighterAlpha`, multiplied.
    public static let highlighterWidthFactor: Double = 3
    public static let highlighterAlpha: Double = 0.45
    /// Redaction blocks are at least this many content pixels.
    public static let minimumRedactionBlock: Double = 8
    /// Duplicates are offset by this many content pixels (× size factor).
    public static let duplicateOffset: Double = 16
    /// Hit-testing tolerance and handle radius in screen points.
    public static let hitTolerance: Double = 6
    public static let handleRadius: Double = 6
    /// Distance of the rotate handle above the top edge, in screen points.
    public static let rotateHandleOffset: Double = 24

    /// 5 neutrals, then 15 hues.
    public static let palette: [AnnotationColor] = [
        AnnotationColor(name: "White", color: RGBAColor(rgb: 0xFFFFFF)),
        AnnotationColor(name: "Silver", color: RGBAColor(rgb: 0xC4C6CC)),
        AnnotationColor(name: "Grey", color: RGBAColor(rgb: 0x8A8D96)),
        AnnotationColor(name: "Graphite", color: RGBAColor(rgb: 0x44464D)),
        AnnotationColor(name: "Black", color: RGBAColor(rgb: 0x111114)),
        AnnotationColor(name: "Red", color: RGBAColor(rgb: 0xF2453D)),
        AnnotationColor(name: "Orange", color: RGBAColor(rgb: 0xF77F2A)),
        AnnotationColor(name: "Amber", color: RGBAColor(rgb: 0xF5A524)),
        AnnotationColor(name: "Yellow", color: RGBAColor(rgb: 0xF2D02B)),
        AnnotationColor(name: "Lime", color: RGBAColor(rgb: 0x9BD43A)),
        AnnotationColor(name: "Green", color: RGBAColor(rgb: 0x3DBE5C)),
        AnnotationColor(name: "Mint", color: RGBAColor(rgb: 0x2FCB9A)),
        AnnotationColor(name: "Teal", color: RGBAColor(rgb: 0x1BA8A0)),
        AnnotationColor(name: "Cyan", color: RGBAColor(rgb: 0x2BC0E4)),
        AnnotationColor(name: "Sky", color: RGBAColor(rgb: 0x4AA3F0)),
        AnnotationColor(name: "Blue", color: RGBAColor(rgb: 0x3366E8)),
        AnnotationColor(name: "Indigo", color: RGBAColor(rgb: 0x5A4FE0)),
        AnnotationColor(name: "Violet", color: RGBAColor(rgb: 0x8B55E8)),
        AnnotationColor(name: "Magenta", color: RGBAColor(rgb: 0xD447C8)),
        AnnotationColor(name: "Pink", color: RGBAColor(rgb: 0xF2558C)),
    ]

    /// Emoji offered by the sticker picker.
    public static let stickers: [String] = [
        "👍", "👎", "👀", "🔥", "✅", "❌", "⚠️", "💡", "⭐", "❤️", "🎉", "🚀",
        "👉", "👈", "👆", "👇", "😀", "😂", "😍", "🤔", "😱", "🙏", "💯", "📌",
    ]
}
