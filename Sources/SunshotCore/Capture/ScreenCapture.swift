import Foundation

/// A window that can be captured (S10), as listed in the window picker.
public struct CapturableWindow: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let title: String
    public let appName: String
    public let width: Int
    public let height: Int

    public init(id: UInt32, title: String, appName: String, width: Int, height: Int) {
        self.id = id
        self.title = title
        self.appName = appName
        self.width = width
        self.height = height
    }

    /// "Safari — Start Page", or the app name alone when the window has no title.
    public var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? appName : "\(appName) — \(trimmed)"
    }

    /// Windows worth offering: big enough to be real windows (not menu-bar extras or 1-px helpers), sorted by app
    /// then title, excluding `excludedApp` (Sunshot itself).
    public static func pickable(_ windows: [CapturableWindow], excludingApp excludedApp: String?) -> [CapturableWindow]
    {
        windows
            .filter { $0.width >= minimumSide && $0.height >= minimumSide && $0.appName != excludedApp }
            .sorted {
                ($0.appName.lowercased(), $0.title.lowercased(), $0.id) < (
                    $1.appName.lowercased(), $1.title.lowercased(), $1.id
                )
            }
    }

    public static let minimumSide = 40
}

public enum ScreenCaptureError: Error, Equatable, Sendable {
    /// Screen Recording permission is not granted (System Settings ▸ Privacy & Security).
    case permissionDenied
    case noDisplay
    case windowNotFound
    case selectionTooSmall
    case failed(String)

    public var title: String {
        switch self {
        case .permissionDenied: "Sunshot needs permission to record the screen"
        default: "Couldn't capture the screen"
        }
    }

    public var reason: String {
        switch self {
        case .permissionDenied:
            "Allow Sunshot in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then try again."
        case .noDisplay: "No display is available to capture."
        case .windowNotFound: "That window is no longer open."
        case .selectionTooSmall: "Drag out a larger area to capture."
        case .failed(let detail): detail
        }
    }
}

/// The area dragged out on the selection overlay, in the overlay's points (top-left origin), which match the
/// captured display's points.
public enum AreaSelection {
    /// Areas smaller than this (either side, in points) are treated as a click and cancel the capture.
    public static let minimumSide: Double = 8

    /// The rectangle spanned by a drag from `start` to `end`, limited to a display of `width` × `height` points.
    public static func rect(
        from start: (x: Double, y: Double), to end: (x: Double, y: Double), displayWidth width: Double,
        displayHeight height: Double
    ) -> LayoutRect {
        func clampX(_ value: Double) -> Double { min(max(value.isFinite ? value : 0, 0), max(width, 0)) }
        func clampY(_ value: Double) -> Double { min(max(value.isFinite ? value : 0, 0), max(height, 0)) }
        let minX = min(clampX(start.x), clampX(end.x))
        let maxX = max(clampX(start.x), clampX(end.x))
        let minY = min(clampY(start.y), clampY(end.y))
        let maxY = max(clampY(start.y), clampY(end.y))
        return LayoutRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether `rect` is big enough to capture.
    public static func isCapturable(_ rect: LayoutRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// Output size in pixels of `rect` on a display with `scale` pixels per point.
    public static func pixelSize(of rect: LayoutRect, scale: Double) -> PixelSize {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        return PixelSize(
            width: Int((rect.width * safeScale).rounded()), height: Int((rect.height * safeScale).rounded()))
    }
}
