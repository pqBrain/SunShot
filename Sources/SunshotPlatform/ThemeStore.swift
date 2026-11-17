public import Foundation
public import SunshotCore
import os

/// Saved themes: one JSON file per theme in `~/Library/Application Support/Sunshot/Themes`.
/// Corrupt files are skipped (and logged), never fatal to the list.
public struct ThemeStore: Sendable {
    public let directory: URL
    private static let log = Logger(subsystem: "app.sunshot", category: "themes")

    public init(directory: URL) {
        self.directory = directory
    }

    /// All readable themes, sorted by name (case-insensitive).
    public func load() -> [Theme] {
        loadEntries().map(\.theme).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Writes `theme` (replacing the file of a theme with the same id, renaming it if the name changed).
    @discardableResult
    public func save(_ theme: Theme) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entries = loadEntries()
        let previous = entries.first { $0.theme.id == theme.id }?.file
        let taken = Set(entries.filter { $0.theme.id != theme.id }.map(\.file.lastPathComponent))
        let file = directory.appendingPathComponent(ThemeName.fileName(for: theme.name, taken: taken))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(theme).write(to: file, options: .atomic)
        if let previous, previous.lastPathComponent != file.lastPathComponent {
            try? FileManager.default.removeItem(at: previous)
        }
        return file
    }

    public func delete(id: String) throws {
        for entry in loadEntries() where entry.theme.id == id {
            try FileManager.default.removeItem(at: entry.file)
        }
    }

    private func loadEntries() -> [(theme: Theme, file: URL)] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { file in
                do {
                    let theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file))
                    guard !theme.name.isEmpty, (try? theme.apply(to: Project())) != nil else {
                        throw DocumentFormatError.invalidJSON("unreadable style")
                    }
                    return (theme, file)
                } catch {
                    Self.log.error("Skipping unreadable theme \(file.lastPathComponent, privacy: .public)")
                    return nil
                }
            }
    }
}

/// One entry of File ▸ Open Recent.
public struct RecentDocument: Equatable, Sendable, Identifiable {
    public var url: URL
    public var bookmark: Data?
    public var id: String { url.path }
    public var name: String { url.deletingPathExtension().lastPathComponent }

    public init(url: URL, bookmark: Data? = nil) {
        self.url = url
        self.bookmark = bookmark
    }
}

/// File ▸ Open Recent, kept in `UserDefaults` (most recent first, at most 10).
public struct RecentDocumentsStore {
    static let key = SettingsStore.prefix + "recentDocuments"
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> RecentList<RecentDocument> {
        let stored = defaults.array(forKey: Self.key) as? [[String: Any]] ?? []
        return RecentList(
            items: stored.compactMap { entry in
                guard let path = entry["path"] as? String else { return nil }
                return RecentDocument(url: URL(fileURLWithPath: path), bookmark: entry["bookmark"] as? Data)
            })
    }

    public func save(_ list: RecentList<RecentDocument>) {
        let stored: [[String: Any]] = list.items.map { item in
            var entry: [String: Any] = ["path": item.url.path]
            if let bookmark = item.bookmark { entry["bookmark"] = bookmark }
            return entry
        }
        defaults.set(stored, forKey: Self.key)
    }
}
