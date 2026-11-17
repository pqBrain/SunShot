public import AppKit
public import Foundation
public import SunshotCore

/// Reads and writes `AppSettings` in `UserDefaults` under the `app.sunshot.` prefix.
public struct SettingsStore {
    public static let prefix = "app.sunshot."
    enum Key: String, CaseIterable {
        case appearance, filenameTemplate, exportFolderPath, exportFolderBookmark, confirmReset, defaultTemplate
        case captureHotkey, captureShortcut, captureDestination
        case suggestDevice, autoBackdropOnImport, askToSaveOnClose, showsMenuBarIcon, annotateOnOpen
        case styleSystemScreenshots, revision
        var name: String { SettingsStore.prefix + rawValue }
    }

    let defaults: UserDefaults
    /// Bumped when a stored choice must be migrated once. 1 (S16): a shortcut capture copied raw before the styled
    /// copy existed becomes the styled copy; a raw choice saved since then is kept.
    static let revision = 1

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
        if defaults.object(forKey: Key.captureHotkey.name) != nil {
            settings.captureHotkeyEnabled = defaults.bool(forKey: Key.captureHotkey.name)
        }
        if let data = defaults.data(forKey: Key.captureShortcut.name),
            let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data), shortcut.isValid
        {
            settings.captureShortcut = shortcut
        }
        if let raw = defaults.string(forKey: Key.captureDestination.name),
            let destination = GlobalCaptureDestination(rawValue: raw)
        {
            settings.globalCaptureDestination = destination
            if destination == .clipboard, defaults.integer(forKey: Key.revision.name) < Self.revision {
                settings.globalCaptureDestination = .styledClipboard
            }
        }
        if defaults.object(forKey: Key.suggestDevice.name) != nil {
            settings.suggestDevice = defaults.bool(forKey: Key.suggestDevice.name)
        }
        if defaults.object(forKey: Key.autoBackdropOnImport.name) != nil {
            settings.autoBackdropOnImport = defaults.bool(forKey: Key.autoBackdropOnImport.name)
        }
        if defaults.object(forKey: Key.askToSaveOnClose.name) != nil {
            settings.askToSaveOnClose = defaults.bool(forKey: Key.askToSaveOnClose.name)
        }
        if defaults.object(forKey: Key.showsMenuBarIcon.name) != nil {
            settings.showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon.name)
        }
        if defaults.object(forKey: Key.annotateOnOpen.name) != nil {
            settings.annotateOnOpen = defaults.bool(forKey: Key.annotateOnOpen.name)
        }
        if defaults.object(forKey: Key.styleSystemScreenshots.name) != nil {
            settings.styleSystemScreenshots = defaults.bool(forKey: Key.styleSystemScreenshots.name)
        }
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
        defaults.set(settings.captureHotkeyEnabled, forKey: Key.captureHotkey.name)
        defaults.set(try? JSONEncoder().encode(settings.captureShortcut), forKey: Key.captureShortcut.name)
        defaults.set(settings.globalCaptureDestination.rawValue, forKey: Key.captureDestination.name)
        defaults.set(settings.suggestDevice, forKey: Key.suggestDevice.name)
        defaults.set(settings.autoBackdropOnImport, forKey: Key.autoBackdropOnImport.name)
        defaults.set(settings.askToSaveOnClose, forKey: Key.askToSaveOnClose.name)
        defaults.set(settings.showsMenuBarIcon, forKey: Key.showsMenuBarIcon.name)
        defaults.set(settings.annotateOnOpen, forKey: Key.annotateOnOpen.name)
        defaults.set(settings.styleSystemScreenshots, forKey: Key.styleSystemScreenshots.name)
        defaults.set(Self.revision, forKey: Key.revision.name)
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
