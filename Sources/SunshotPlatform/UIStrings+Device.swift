public import SunshotCore

/// S12 copy: Device section, template gallery and Settings ▸ Device Mockups.
extension UIStrings {
    public static let deviceSection = "Device"
    public static let deviceNone = "None"
    public static let deviceFinish = "Finish"
    public static let deviceOrientation = "Orientation"
    public static let devicePortrait = "Portrait"
    public static let deviceLandscape = "Landscape"
    public static let deviceArrangement = "Layout"
    public static let deviceSuggestionUse = "Use"
    public static let suggestDeviceSetting = "Suggest the device that matches imported images"
    public static let deviceMockupsSetting = "Device mockups"
    public static let templatesTitle = "Templates"
    public static let templatesScreens = "Screens"
    public static let templatesDevices = "Devices"
    public static let templatesHint = "Templates restyle the document. Your content stays."
    public static let templatesSample = "Previews use sample content until you add an image."
    public static let close = "Close"

    /// VoiceOver label of a device tile: "Device: Phone, selected".
    public static func deviceOption(_ name: String, selected: Bool) -> String {
        "Device: \(name)" + (selected ? ", selected" : "")
    }

    /// VoiceOver label of a finish swatch: "Finish: Graphite, selected".
    public static func finishOption(_ name: String, selected: Bool) -> String {
        "Finish: \(name)" + (selected ? ", selected" : "")
    }

    /// "Best with 1080 × 2340 px".
    public static func recommendedMedia(_ size: PixelSize) -> String {
        "Best with \(size.width) × \(size.height) px"
    }

    /// "This image fits a Phone" / "This image fits a Tablet (landscape)".
    public static func deviceSuggestion(_ suggestion: DeviceSuggestion) -> String {
        let article = suggestion.model.name.first.map { "AEIOU".contains($0) } == true ? "an" : "a"
        let turned = suggestion.landscape ? " (landscape)" : ""
        return "This image fits \(article) \(suggestion.model.name)\(turned)"
    }

    /// Template card label: "Template: Pocket Spotlight, A phone on a sunrise gradient., current".
    public static func templateOption(_ template: DocumentTemplate, current: Bool) -> String {
        "Template: \(template.name), \(template.summary)" + (current ? ", current" : "")
    }
}
