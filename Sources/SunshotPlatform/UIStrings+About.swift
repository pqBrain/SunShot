import Foundation

/// Settings tabs and the About tab.
extension UIStrings {
    public static let generalTab = "General"
    public static let aboutTab = "About"

    public static let aboutTagline = "A lightweight screenshot beautifier for your Mac."
    public static let aboutAuthor = "Author"
    public static let aboutAuthorName = "Peter Quoc"
    public static let aboutSystem = "System"
    public static let copyDiagnostics = "Copy Diagnostics"
    public static let copyDiagnosticsHint = "Paste this into bug reports."
    public static let diagnosticsCopied = "Copied"
    public static let aboutPrivacyTitle = "Privacy"
    public static let aboutPrivacyBody =
        "Sunshot works on your Mac. Your screenshots and documents stay here, and nothing is sent anywhere. "
        + "Only Capture Website goes online, to load the page you ask for."
    public static let aboutCreditsTitle = "Credits"
    public static let aboutCreditsBody =
        "Built with SwiftUI, Core Image, ScreenCaptureKit and AVFoundation. No third-party code."
    public static func aboutCopyright(year: Int) -> String { "© \(year) \(aboutAuthorName)" }
}
