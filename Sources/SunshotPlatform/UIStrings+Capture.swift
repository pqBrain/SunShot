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
    public static let removeCrop = "Remove Crop"
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
    public static let captureAreaHint = "Drag to choose an area. Press Esc to cancel."
    public static let windowPickerTitle = "Capture a Window"
    public static let windowPickerEmpty = "No windows to capture."
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
    public static let globalCaptureShortcut = "Capture Area from anywhere (⌥⇧⌘4)"
    public static let globalCaptureShortcutHint =
        "Lets ⌥⇧⌘4 start an area capture even when Sunshot is in the background."

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

    /// "Safari — Start Page, 1440 × 900".
    public static func windowLabel(_ window: CapturableWindow) -> String {
        "\(window.displayName), \(pixelSize(width: window.width, height: window.height))"
    }
}
