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
    /// Template opened for new documents. Only "Screenshot" exists until the template gallery (S12).
    public var defaultTemplate: String

    public static let screenshotTemplate = "Screenshot"
    public static let defaults = AppSettings()

    public init(
        appearance: AppearanceSetting = .system, filenameTemplate: String = SunshotDefaults.filenameTemplate,
        exportFolder: URL? = nil, confirmReset: Bool = true, defaultTemplate: String = AppSettings.screenshotTemplate
    ) {
        self.appearance = appearance
        self.filenameTemplate = filenameTemplate
        self.exportFolder = exportFolder
        self.confirmReset = confirmReset
        self.defaultTemplate = defaultTemplate
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
