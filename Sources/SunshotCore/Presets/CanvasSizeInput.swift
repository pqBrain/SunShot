import Foundation

/// One typed side of a custom canvas size.
public enum CanvasSideInput: Hashable, Sendable {
    /// Empty field: that side follows the Auto canvas.
    case auto
    case pixels(Int)
    /// Not a whole number in 1…`SunshotDefaults.maxCanvasSide`.
    case invalid

    /// Accepts whole numbers 1…16384 (an optional "px" suffix is fine); empty means Auto.
    public static func parse(_ text: String) -> CanvasSideInput {
        var trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("px") { trimmed = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        if trimmed.isEmpty || trimmed == "auto" { return .auto }
        guard let value = Int(trimmed), (1...SunshotDefaults.maxCanvasSide).contains(value) else { return .invalid }
        return .pixels(value)
    }

    var pixels: Int? {
        if case .pixels(let value) = self { return value }
        return nil
    }

    /// Both sides parsed into a canvas spec, or nil when either is invalid. Both empty = Auto.
    public static func canvas(width: String, height: String) -> CanvasSpec? {
        let (w, h) = (parse(width), parse(height))
        guard w != .invalid, h != .invalid else { return nil }
        if w == .auto, h == .auto { return .auto }
        return .custom(CustomCanvasSize(width: w.pixels, height: h.pixels))
    }
}

/// Arrow-key movement through a grid of `count` items laid out in rows of `columns`.
public enum GridNavigation {
    public enum Direction: Sendable { case left, right, up, down }

    /// The index focus moves to; stays put at the edges. A nil `index` lands on the first item.
    public static func move(from index: Int?, _ direction: Direction, count: Int, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index, (0..<count).contains(index) else { return 0 }
        let step = max(1, columns)
        let target =
            switch direction {
            case .left: index - 1
            case .right: index + 1
            case .up: index - step
            case .down: index + step
            }
        return (0..<count).contains(target) ? target : index
    }
}
