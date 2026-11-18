public import Foundation
public import SunshotCore

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
