public import Foundation

/// App appearance override (System follows the OS). Exports never depend on it.
public enum AppearanceSetting: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// User preferences (not document state: Start Over and new documents never change them).
public struct AppSettings: Equatable, Sendable {
    public var appearance: AppearanceSetting
    /// Export file-name template (S4 tokens). Empty means the default.
    public var filenameTemplate: String
    /// Folder exports are written to without a save panel; nil asks every time.
    public var exportFolder: URL?
    public var confirmReset: Bool
    /// Template opened for new documents and Start Over: a template id (S12), or the name saved by S7.
    public var defaultTemplate: String
    /// S10: the global Capture Area shortcut (⇧⌘S unless changed) works while Sunshot is in the background.
    /// S16: on by default, since Sunshot keeps running in the menu bar for quick captures.
    public var captureHotkeyEnabled: Bool
    /// S10: the keys of the global Capture Area shortcut (Settings ▸ Shortcut).
    public var captureShortcut: GlobalShortcut
    /// S17: the global Capture Window shortcut (⇧⌘W unless changed) and whether it is on.
    public var windowHotkeyEnabled: Bool
    public var windowShortcut: GlobalShortcut
    /// S17: the global Open Studio shortcut (⇧⌘0 unless changed) and whether it is on.
    public var studioHotkeyEnabled: Bool
    public var studioShortcut: GlobalShortcut
    /// S10: what a global-shortcut capture does: open in the editor, or copy to the clipboard (S16: styled, by default).
    public var globalCaptureDestination: GlobalCaptureDestination
    /// S12: offer the device that matches imported media (Settings ▸ Device Mockups).
    public var suggestDevice: Bool
    /// S7: the first image of a document with the default backdrop gets an auto background made from its colours.
    public var autoBackdropOnImport: Bool
    /// Closing a never-saved document with content asks "Save changes?". Off: it is discarded without asking.
    public var askToSaveOnClose: Bool
    /// S16: Sunshot shows an icon in the menu bar and keeps running there after its window closes.
    public var showsMenuBarIcon: Bool
    /// S16: a capture opened in the studio starts in Annotate mode.
    public var annotateOnOpen: Bool
    /// S16: screenshots the macOS screenshot tool copies to the clipboard (⌃⌘⇧3/4, ⌘⇧5) are replaced there with
    /// the default style's render, frame None.
    public var styleSystemScreenshots: Bool
    /// S18: look for a new Sunshot release once a day (Sunshot ▸ Check for Updates… works either way).
    public var checkForUpdatesAutomatically: Bool

    public static let screenshotTemplate = "Screenshot"
    public static let defaults = AppSettings()

    public init(
        appearance: AppearanceSetting = .system, filenameTemplate: String = SunshotDefaults.filenameTemplate,
        exportFolder: URL? = nil, confirmReset: Bool = true, defaultTemplate: String = AppSettings.screenshotTemplate,
        captureHotkeyEnabled: Bool = true, captureShortcut: GlobalShortcut = .default,
        globalCaptureDestination: GlobalCaptureDestination = .styledClipboard, suggestDevice: Bool = true,
        autoBackdropOnImport: Bool = true, askToSaveOnClose: Bool = true, showsMenuBarIcon: Bool = true,
        annotateOnOpen: Bool = true, styleSystemScreenshots: Bool = true, windowHotkeyEnabled: Bool = true,
        windowShortcut: GlobalShortcut = GlobalShortcutAction.captureWindow.defaultShortcut,
        studioHotkeyEnabled: Bool = true,
        studioShortcut: GlobalShortcut = GlobalShortcutAction.openStudio.defaultShortcut,
        checkForUpdatesAutomatically: Bool = true
    ) {
        self.checkForUpdatesAutomatically = checkForUpdatesAutomatically
        self.windowHotkeyEnabled = windowHotkeyEnabled
        self.windowShortcut = windowShortcut
        self.studioHotkeyEnabled = studioHotkeyEnabled
        self.studioShortcut = studioShortcut
        self.styleSystemScreenshots = styleSystemScreenshots
        self.showsMenuBarIcon = showsMenuBarIcon
        self.annotateOnOpen = annotateOnOpen
        self.askToSaveOnClose = askToSaveOnClose
        self.autoBackdropOnImport = autoBackdropOnImport
        self.captureHotkeyEnabled = captureHotkeyEnabled
        self.captureShortcut = captureShortcut
        self.globalCaptureDestination = globalCaptureDestination
        self.appearance = appearance
        self.filenameTemplate = filenameTemplate
        self.exportFolder = exportFolder
        self.confirmReset = confirmReset
        self.defaultTemplate = defaultTemplate
        self.suggestDevice = suggestDevice
    }

    /// The template exports use: the setting, or the default when it is blank.
    public var effectiveFilenameTemplate: String {
        let trimmed = filenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SunshotDefaults.filenameTemplate : filenameTemplate
    }
}

/// The live preview under the file-name field in Settings.
public enum FilenamePreview {
    public static let defaultFormatWarning = "Using the default format"

    /// The example name for `template` (S4 rules) and a warning when the default is used instead.
    public static func preview(
        template: String, date: Date, width: Int = 1128, height: Int = 728, scale: ExportScale = .x1,
        format: ExportFormat = .png, timeZone: TimeZone = .current, random: () -> String = { "a1b2c3" }
    ) -> (name: String, warning: String?) {
        let context = FilenameContext(scale: scale, date: date, width: width, height: height, format: format)
        let name = FilenameTemplate.fileName(template: template, context: context, timeZone: timeZone, random: random)
        let blank = template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (name, blank ? defaultFormatWarning : nil)
    }
}

/// File names for exports written straight into the default folder.
public enum ExportFileNaming {
    /// `name` if free, else `name 2.ext`, `name 3.ext`… (never overwrites).
    public static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }
}

/// Most-recent-first list of document paths, without duplicates, capped at `limit`.
public struct RecentList<Item: Equatable & Sendable>: Equatable, Sendable {
    public static var limit: Int { 10 }
    public private(set) var items: [Item]

    public init(items: [Item] = []) {
        self.items = Array(items.prefix(Self.limit))
    }

    public mutating func note(_ item: Item, matching same: (Item, Item) -> Bool = { $0 == $1 }) {
        items.removeAll { same($0, item) }
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func remove(where predicate: (Item) -> Bool) { items.removeAll(where: predicate) }
    public mutating func clear() { items.removeAll() }
}
