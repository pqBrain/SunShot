public import SunshotCore

/// Crop and capture copy (S10).
extension UIStrings {
    // Crop
    public static let cropButton = "Crop"
    public static let cropAccessibility = "Crop the image, ⌥⌘C"
    public static let cropTitle = "Crop Image"
    public static let cropRatio = "Ratio"
    public static let cropReset = "Reset"
    public static let cropResetAccessibility = "Reset the crop to the whole image"
    public static let cropApply = "Apply"
    public static let cropArea = "Crop area"
    public static let cropHint = "Drag the corners or edges to crop. Drag inside to move. The original image is kept."

    public static func cropAspectName(_ aspect: CropAspect) -> String {
        switch aspect {
        case .free: "Free"
        case .original: "Original"
        case .square: "1:1"
        case .landscape4x3: "4:3"
        case .portrait3x4: "3:4"
        case .landscape3x2: "3:2"
        case .portrait2x3: "2:3"
        case .wide16x9: "16:9"
        case .tall9x16: "9:16"
        }
    }

    // Capture
    public static let captureMenu = "Capture"
    public static let captureAccessibility = "Capture the screen or a website"
    public static let captureArea = "Capture Area…"
    public static let captureWindow = "Capture Window…"
    public static let captureWebsite = "Capture Website…"
    public static let captureButton = "Capture"
    public static let websiteTitle = "Capture a Website"
    public static let websiteAddress = "Website address"
    public static let websitePlaceholder = "example.com"
    public static let captureViewport = "Viewport"
    public static let captureFullPage = "Full page"
    public static let captureFullPageHint = "Captures the whole scrolling page, up to 16,000 pixels tall."
    public static let captureDelay = "Delay"
    public static let capturingWebsite = "Loading the page…"
    public static let openPrivacySettings = "Open System Settings"
    public static let globalCaptureShortcut = "Capture Area from anywhere"
    public static func globalCaptureShortcutHint(_ shortcut: GlobalShortcut) -> String {
        "Lets \(shortcut) start an area capture even when Sunshot is in the background."
    }
    public static let captureShortcutLabel = "Shortcut"
    /// S17: the Settings row title of each global shortcut.
    public static func globalShortcutTitle(_ action: GlobalShortcutAction) -> String {
        switch action {
        case .captureArea: globalCaptureShortcut
        case .captureWindow: "Capture Window from anywhere"
        case .openStudio: "Open Studio from anywhere"
        }
    }
    public static func globalShortcutHint(_ action: GlobalShortcutAction, _ shortcut: GlobalShortcut) -> String {
        switch action {
        case .captureArea: globalCaptureShortcutHint(shortcut)
        case .captureWindow: "Lets \(shortcut) start a window capture even when Sunshot is in the background."
        case .openStudio: "Lets \(shortcut) bring the studio forward from any app."
        }
    }
    public static func globalShortcutName(_ action: GlobalShortcutAction) -> String {
        switch action {
        case .captureArea: "Capture Area"
        case .captureWindow: "Capture Window"
        case .openStudio: "Open Studio"
        }
    }
    /// S17: the recorded keys already belong to another of Sunshot's global shortcuts.
    public static func shortcutInUse(by action: GlobalShortcutAction) -> String {
        "\(globalShortcutName(action)) already uses these keys."
    }
    public static let recordShortcutPrompt = "Type shortcut…"
    public static let recordShortcutHelp = "Click, then press the new keys. Esc cancels."
    public static let restoreDefaultShortcut = "Restore Default"
    public static let shortcutUnavailable = "Another app is using this shortcut. Choose different keys."
    public static func shortcutProblem(_ problem: GlobalShortcut.Problem) -> String {
        switch problem {
        case .needsModifier: "Use ⌃ or ⌥ (or ⇧⌘) with the key, or a function key."
        case .reservedBySystem: "macOS uses these keys for its own screenshots."
        }
    }
    public static let afterShortcutCapture = "After a shortcut capture"
    public static func captureDestinationName(_ destination: GlobalCaptureDestination) -> String {
        switch destination {
        case .editor: "Open in Sunshot"
        case .clipboard: "Copy to clipboard"
        case .styledClipboard: "Copy with default style"
        }
    }
    public static let copiedToClipboard = "Screenshot copied to clipboard"

    public static func viewportName(_ viewport: WebViewport) -> String {
        let name =
            switch viewport {
            case .desktop: "Desktop"
            case .laptop: "Laptop"
            case .tablet: "Tablet"
            case .phone: "Phone"
            }
        return "\(name) (\(viewport.width) px)"
    }

    /// "2 s".
    public static func delayLabel(_ seconds: Double) -> String { "\(Int(seconds.rounded())) s" }
}
