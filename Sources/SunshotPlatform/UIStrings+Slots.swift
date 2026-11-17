/// S15 copy: the Screenshots inspector section.
extension UIStrings {
    public static let screenshotsSection = "Screenshots"
    public static let screenshotLayout = "Layout"
    public static let screenshotLayoutNone = "One Screenshot"
    public static let screenshotMain = "Main"
    public static let screenshotChoose = "Choose…"
    public static let screenshotRemove = "Remove"
    public static let screenshotSameAsMain = "Shows the main image"
    public static let screenshotDragHint = "Drag onto another screenshot to swap their places."
    public static let screenshotFailedTitle = "Couldn't use this image"
    public static let screenshotsDeviceHint = "Each device can show its own screenshot."
    public static let screenshotsSlotsHint =
        "Choose or drop an image for each screenshot. Empty ones show the main image."
    public static let screenshotsLayoutHint = "Paste (⌘V) or capture again to add another screenshot."
    public static let screenshotsDeviceLayoutHint = "Remove the device to use a screenshot layout."

    /// The hint under the Screenshots section.
    public static func screenshotsHint(hasDevice: Bool, multiple: Bool) -> String {
        switch (hasDevice, multiple) {
        case (true, true): screenshotsDeviceHint
        case (true, false): screenshotsDeviceLayoutHint
        case (false, true): screenshotsSlotsHint
        case (false, false): screenshotsLayoutHint
        }
    }

    /// Row title: "Main" or "Screenshot 2" (screenshot number 1 is the second picture).
    public static func screenshotName(number: Int) -> String {
        number == 0 ? screenshotMain : "Screenshot \(number + 1)"
    }

    /// Notice after paste or capture added a screenshot: "Added as screenshot 2 · Side by Side · border trimmed".
    public static func screenshotAdded(number: Int, layout: String?, trimmed: Bool = false) -> String {
        "Added as screenshot \(number + 1)" + (layout.map { " · \($0)" } ?? "") + (trimmed ? " · border trimmed" : "")
    }

    /// Notice when a pasted or captured image had its solid border trimmed.
    public static let screenshotTrimmed = "Trimmed the solid border around the screenshot"

    /// Notice when every screenshot is filled: "All 4 screenshots are filled. Remove one to add another."
    public static func screenshotsFull(count: Int) -> String {
        "All \(count) screenshots are filled. Remove one to add another."
    }

    /// VoiceOver label of a slot row: "Screenshot 2, shows the main image".
    public static func screenshotRow(_ name: String, hasImage: Bool) -> String {
        hasImage ? name : "\(name), \(screenshotSameAsMain.lowercased())"
    }

    /// VoiceOver label of a Choose button: "Choose image for Screenshot 2".
    public static func screenshotChooseAccessibility(_ name: String) -> String { "Choose image for \(name)" }

    /// VoiceOver label of a Remove button: "Remove image from Screenshot 2".
    public static func screenshotRemoveAccessibility(_ name: String) -> String { "Remove image from \(name)" }
}
