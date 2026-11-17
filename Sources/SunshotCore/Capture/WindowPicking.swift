import Foundation

/// S16: hover-to-pick window capture, like the system's own window screenshot: the window under the pointer is
/// highlighted and a click captures it. Windows arrive front to back, so the first one containing the point is
/// the visible one.
public enum WindowPicking {
    /// Windows that can be hovered: on screen with a known frame, big enough to be real windows, not `excludedApp`.
    /// Front-to-back order is kept.
    public static func candidates(
        _ windows: [CapturableWindow], excludingApp excludedApp: String?
    )
        -> [CapturableWindow]
    {
        windows.filter {
            $0.frame != nil && $0.width >= CapturableWindow.minimumSide && $0.height >= CapturableWindow.minimumSide
                && $0.appName != excludedApp
        }
    }

    /// The front-most window containing `point` (global display points, top-left origin), or nil over the desktop.
    public static func window(at point: (x: Double, y: Double), in windows: [CapturableWindow]) -> CapturableWindow? {
        windows.first { window in
            guard let frame = window.frame else { return false }
            return point.x >= frame.x && point.x < frame.x + frame.width && point.y >= frame.y
                && point.y < frame.y + frame.height
        }
    }

    /// `rect` (global, top-left origin) in the coordinates of a screen whose global frame is `screen` (top-left
    /// origin too): the overlay on that screen draws the highlight there.
    public static func local(_ rect: LayoutRect, on screen: LayoutRect) -> LayoutRect {
        LayoutRect(x: rect.x - screen.x, y: rect.y - screen.y, width: rect.width, height: rect.height)
    }

    /// A screen frame from AppKit's bottom-left-origin global space to the top-left-origin space window frames use;
    /// `mainHeight` is the height of the main (menu-bar) display.
    public static func topLeftFrame(
        x: Double, y: Double, width: Double, height: Double, mainHeight: Double
    ) -> LayoutRect {
        LayoutRect(x: x, y: mainHeight - y - height, width: width, height: height)
    }
}
