public import Foundation

/// One image file in a batch. Holds a file reference only; pixels are decoded on demand.
public struct BulkItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    /// The URL whose security scope covers this file (the chosen or dropped folder, or the file itself).
    public let accessURL: URL

    public init(url: URL, accessURL: URL? = nil, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.accessURL = accessURL ?? url
    }

    /// `shot.png`.
    public var displayName: String { url.lastPathComponent }
    /// `shot` (the `{NAME}` file-name token).
    public var baseName: String { url.deletingPathExtension().lastPathComponent }
    /// Two items are the same file when their standardized paths match.
    public var pathKey: String { url.standardizedFileURL.path }
}

/// What `BulkBatch.add` did with the offered items.
public struct BulkAddResult: Hashable, Sendable {
    public var added = 0
    public var duplicates = 0
    public var overLimit = 0

    public init(added: Int = 0, duplicates: Int = 0, overLimit: Int = 0) {
        self.added = added
        self.duplicates = duplicates
        self.overLimit = overLimit
    }

    public var notAdded: Int { duplicates + overLimit }
}

/// The ordered list of batch items and the selection. All items share the document's one `Project`.
public struct BulkBatch: Hashable, Sendable {
    /// Most items a batch holds.
    public static let maxItems = 500

    public private(set) var items: [BulkItem] = []
    public private(set) var selectedID: UUID?

    public init(items: [BulkItem] = []) {
        add(items)
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var selectedIndex: Int? { selectedID.flatMap(index(of:)) }
    public var selectedItem: BulkItem? { selectedIndex.map { items[$0] } }

    public func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    /// Appends items whose file isn't already in the batch, up to `maxItems`. Selects the first added item when
    /// nothing was selected.
    @discardableResult
    public mutating func add(_ newItems: [BulkItem]) -> BulkAddResult {
        var result = BulkAddResult()
        var known = Set(items.map(\.pathKey))
        var firstAdded: UUID?
        for item in newItems {
            guard !known.contains(item.pathKey) else {
                result.duplicates += 1
                continue
            }
            guard items.count < Self.maxItems else {
                result.overLimit += 1
                continue
            }
            known.insert(item.pathKey)
            items.append(item)
            firstAdded = firstAdded ?? item.id
            result.added += 1
        }
        if selectedID == nil { selectedID = firstAdded }
        return result
    }

    /// Selects `id`. Returns false (selection unchanged) when it isn't in the batch.
    @discardableResult
    public mutating func select(_ id: UUID) -> Bool {
        guard index(of: id) != nil else { return false }
        selectedID = id
        return true
    }

    /// Moves the selection by `offset` (← = -1, → = +1), stopping at the ends. Returns whether it moved.
    @discardableResult
    public mutating func selectAdjacent(_ offset: Int) -> Bool {
        guard let current = selectedIndex else { return false }
        let target = min(max(current + offset, 0), items.count - 1)
        guard target != current else { return false }
        selectedID = items[target].id
        return true
    }

    /// Removes `id`; if it was selected, the next item (or the previous one at the end) becomes selected.
    public mutating func remove(_ id: UUID) {
        guard let index = index(of: id) else { return }
        items.remove(at: index)
        guard selectedID == id else { return }
        selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }

    public mutating func removeAll() {
        items.removeAll()
        selectedID = nil
    }

    /// Moves `id` so it ends up at `destination` (clamped). Returns whether the order changed.
    @discardableResult
    public mutating func move(_ id: UUID, to destination: Int) -> Bool {
        guard let source = index(of: id) else { return false }
        let target = min(max(destination, 0), items.count - 1)
        guard target != source else { return false }
        let item = items.remove(at: source)
        items.insert(item, at: target)
        return true
    }

    /// Moves `id` one place left (-1) or right (+1). No-op at the ends.
    @discardableResult
    public mutating func nudge(_ id: UUID, by offset: Int) -> Bool {
        guard let source = index(of: id) else { return false }
        return move(id, to: source + offset)
    }

    /// Moves `id` to where `target` is now (drag-and-drop onto another thumbnail).
    @discardableResult
    public mutating func move(_ id: UUID, onto target: UUID) -> Bool {
        guard let destination = index(of: target) else { return false }
        return move(id, to: destination)
    }
}
