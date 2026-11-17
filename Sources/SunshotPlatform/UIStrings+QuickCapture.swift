public import SunshotCore

/// S16 copy: menu bar, quick capture, default style, hover window picking, Screenshot ⇄ Code.
extension UIStrings {
    // Menu bar
    public static let menuBarTitle = "Sunshot"
    public static let menuCaptureArea = "Capture Area"
    public static let menuCaptureWindow = "Capture Window"
    public static let menuCaptureAreaToStudio = "Capture Area into Studio"
    public static let menuCaptureWindowToStudio = "Capture Window into Studio"
    public static let menuOpenStudio = "Open Studio"
    public static let menuSettings = "Settings…"
    public static let menuHideIcon = "Hide Menu Bar Icon"
    public static let menuQuit = "Quit Sunshot"
    public static func menuDestination(_ destination: GlobalCaptureDestination) -> String {
        "Shortcut: \(captureDestinationName(destination).lowercased())"
    }

    // Default style
    public static let saveDefaultStyle = "Save as Default Style"
    public static let saveDefaultStyleAccessibility =
        "Save the current style and layout as the default for quick captures and new documents"
    public static let defaultStyleSection = "Default style"
    public static let defaultStyleNone = "Not set: quick captures use the default template"
    public static func defaultStyleSaved(_ date: String) -> String { "Saved \(date)" }
    public static let defaultStyleHint =
        "In the studio, choose Save as Default Style to style quick captures and start new documents that way."
    public static let clearDefaultStyle = "Clear"
    public static let setAsDefault = "Set as Default"
    public static let isDefaultStyle = "Default Style"
    public static let setAsDefaultHelp =
        "Use this backdrop, frame and layout for shortcut captures copied to the clipboard and for new documents"
    public static let isDefaultStyleHelp = "Shortcut captures are copied with this style"

    // Screenshot layouts on the canvas
    public static let deletePickedScreenshot = "Delete this screenshot (Delete)"
    public static let reorderPickedScreenshot = "Drag onto another screenshot to swap their places"

    // Settings
    public static let menuBarSection = "Menu bar & quick capture"
    public static let showMenuBarIconSetting = "Show Sunshot in the menu bar"
    public static let showMenuBarIconHint =
        "Sunshot keeps running in the menu bar after its window closes, so the shortcut always works."
    public static let styleSystemScreenshotsSetting = "Style macOS screenshots on the clipboard"
    public static let styleSystemScreenshotsHint =
        "Screenshots copied with ⌃⌘⇧4 or ⌘⇧5 (Clipboard) are swapped for the default style, without a frame."
    public static let systemScreenshotStyled = "Screenshot styled on the clipboard"
    public static let annotateOnOpenSetting = "Open captures in Annotate mode"
    public static let annotateOnOpenHint = "Captures opened in the studio start with the annotation tools."

    // Hover window picking
    public static let windowPickHint = "Click a window to capture it. Space switches to an area. Esc cancels."
    public static let areaSwitchHint = "Drag to choose an area. Space picks a window. Esc cancels."
    public static func windowPickLabel(_ window: CapturableWindow) -> String {
        "\(window.displayName) — \(pixelSize(width: window.width, height: window.height))"
    }

    // Screenshot ⇄ Code
    public static let contentKindAccessibility = "Content: screenshot or code"
    public static func contentKindName(_ kind: ContentKind) -> String {
        switch kind {
        case .screenshot: "Screenshot"
        case .code: "Code"
        }
    }
    public static func contentKindHelp(_ kind: ContentKind) -> String {
        switch kind {
        case .screenshot: "Show the screenshot (your code is kept)"
        case .code: "Show the code snippet (your screenshot is kept)"
        }
    }
}
