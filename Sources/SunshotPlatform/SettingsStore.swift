public import AppKit
public import Foundation
public import SunshotCore

/// Reads and writes `AppSettings` in `UserDefaults` under the `app.sunshot.` prefix.
public struct SettingsStore {
    public static let prefix = "app.sunshot."
    enum Key: String, CaseIterable {
        case appearance, filenameTemplate, exportFolderPath, exportFolderBookmark, confirmReset, defaultTemplate
        var name: String { SettingsStore.prefix + rawValue }
    }

    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        var settings = AppSettings()
        if let raw = defaults.string(forKey: Key.appearance.name), let value = AppearanceSetting(rawValue: raw) {
            settings.appearance = value
        }
        if let template = defaults.string(forKey: Key.filenameTemplate.name) { settings.filenameTemplate = template }
        if defaults.object(forKey: Key.confirmReset.name) != nil {
            settings.confirmReset = defaults.bool(forKey: Key.confirmReset.name)
        }
        if let template = defaults.string(forKey: Key.defaultTemplate.name) { settings.defaultTemplate = template }
        settings.exportFolder = BookmarkedURL.resolve(
            bookmark: defaults.data(forKey: Key.exportFolderBookmark.name),
            path: defaults.string(forKey: Key.exportFolderPath.name))
        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.appearance.rawValue, forKey: Key.appearance.name)
        defaults.set(settings.filenameTemplate, forKey: Key.filenameTemplate.name)
        defaults.set(settings.confirmReset, forKey: Key.confirmReset.name)
        defaults.set(settings.defaultTemplate, forKey: Key.defaultTemplate.name)
        if let folder = settings.exportFolder {
            if defaults.string(forKey: Key.exportFolderPath.name) != folder.path {
                defaults.set(folder.path, forKey: Key.exportFolderPath.name)
                defaults.set(BookmarkedURL.bookmark(for: folder), forKey: Key.exportFolderBookmark.name)
            }
        } else {
            defaults.removeObject(forKey: Key.exportFolderPath.name)
            defaults.removeObject(forKey: Key.exportFolderBookmark.name)
        }
    }
}

/// Security-scoped bookmarks so files and folders the user chose stay reachable after relaunch (sandbox).
public enum BookmarkedURL {
    public static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    /// The bookmark's URL (access started if it is security-scoped), else the stored path.
    public static func resolve(bookmark: Data?, path: String?) -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &stale)
            {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
            if let url = try? URL(
                resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            {
                return url
            }
        }
        return path.map { URL(fileURLWithPath: $0) }
    }
}

extension AppearanceSetting {
    /// The app-wide appearance override; nil follows the OS.
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    /// Applies the override to every window and popover of the app.
    @MainActor
    public func apply(to application: NSApplication) {
        application.appearance = appearanceName.flatMap { NSAppearance(named: $0) }
    }
}
