public import SunshotCore

/// S7 copy: documents, themes, settings and menus.
extension UIStrings {
    public static let untitled = "Untitled"
    public static let documentOpenFailed = "Can't open this document"
    public static let saveFailed = "Couldn't save the document"
    public static let fileNotFound = "File not found"
    public static let openWithPlaceholders = "Open with Placeholders"
    public static let placeholdersUsed = "Missing images were replaced with placeholders"
    public static let exportFolderUnavailable = "The default export folder isn't available. Choose where to save."
    public static func exportedTo(_ name: String) -> String { "Exported \(name)" }

    public static let showInspector = "Show Inspector"
    public static let hideInspector = "Hide Inspector"
    public static let clearMenu = "Clear Menu"
    public static let cancel = "Cancel"

    // Start Over
    public static let startOverTitle = "Start over?"
    public static let startOverMessage =
        "This removes the image and resets every style to the defaults. You can undo it."
    public static let startOverButton = "Start Over"

    // Close
    public static func saveChangesTitle(_ name: String) -> String { "Save changes to \(name)?" }
    public static let saveChangesMessage = "Your changes will be lost if you don't save them."
    public static let save = "Save"
    public static let dontSave = "Don't Save"
    public static let dontAskAgain = "Don't ask again"
    public static let askToSaveSetting = "Ask to save untitled documents when closing"
    public static let askToSaveSettingHint = "When off, closing an unsaved document discards it."

    // Themes
    public static let saveTheme = "Save…"
    public static let saveThemeTitle = "Save Theme"
    public static let saveThemeAccessibility = "Save current style as a theme"
    public static let themeNamePrompt = "Theme name"
    public static let replace = "Replace"
    public static let rename = "Rename…"
    public static let duplicate = "Duplicate"
    public static let delete = "Delete"
    public static let renameThemeTitle = "Rename Theme"
    public static let noSavedThemes = "No saved themes"
    public static let manageThemes = "Manage"
    public static func themeAccessibility(_ title: String) -> String { "Theme: \(title)" }

    // Settings
    public static let settingsTitle = "Settings"
    public static let appearance = "Appearance"
    public static func appearanceName(_ value: AppearanceSetting) -> String {
        switch value {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    public static let filenameFormat = "Filename format"
    public static let filenameTokensHint = "{DATE} {TEMPLATE} {SCALE} {RANDOM} {WIDTH} {HEIGHT}"
    public static let exportFolder = "Default export folder"
    public static let exportFolderNone = "Ask each time"
    public static let choose = "Choose…"
    public static let clear = "Clear"
    public static let confirmReset = "Confirm before resetting"
    public static let defaultTemplate = "Default template"
}
