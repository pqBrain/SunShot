import Foundation

/// The tools on the frozen-screen capture overlay: `area` drags out the region to capture, the others mark up
/// the frozen screen first. Marks are ordinary `Annotation`s in display points.
public enum FreezeTool: String, CaseIterable, Sendable {
    case area, arrow, rectangle, pen, highlighter

    /// Single-key shortcut on the overlay.
    public var shortcut: Character {
        switch self {
        case .area: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .pen: "p"
        case .highlighter: "h"
        }
    }

    public static func forShortcut(_ key: Character) -> FreezeTool? {
        let lower = Character(key.lowercased())
        return allCases.first { $0.shortcut == lower }
    }

    /// The annotation kind the tool draws (nil for `area`).
    public var kind: AnnotationKind? {
        switch self {
        case .area: nil
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .pen: .pen
        case .highlighter: .highlighter
        }
    }

    /// Stroke width in display points.
    public var lineWidth: Double {
        switch self {
        case .highlighter: 14
        case .arrow: 4
        default: 3
        }
    }
}

/// Colours offered on the overlay, picked with keys 1…5.
public enum FreezePalette {
    public static let colors: [RGBAColor] = [
        AnnotationDefaults.color, RGBAColor(rgb: 0xFFC800), RGBAColor(rgb: 0x34C759), RGBAColor(rgb: 0x0A84FF),
        RGBAColor(rgb: 0x1D1D1F),
    ]
}

/// Builds the mark for a finished drag. Pure, so the overlay holds no logic.
public enum FreezeMarks {
    /// Drags shorter than this (display points) are clicks and make no mark.
    public static let minimumDrag: Double = 3

    /// A mark for `tool` along `path` (display points), or nil for `area` and for a click.
    public static func mark(
        tool: FreezeTool, path: [AnnotationPoint], color: RGBAColor = AnnotationDefaults.color
    ) -> Annotation? {
        guard let kind = tool.kind, let first = path.first, let last = path.last else { return nil }
        guard path.contains(where: { $0.distance(to: first) >= minimumDrag }) else { return nil }
        let points: [AnnotationPoint] =
            switch kind {
            case .pen, .highlighter: path
            default: [first, last]
            }
        return Annotation(kind: kind, points: points, color: color, lineWidth: tool.lineWidth)
    }
}
