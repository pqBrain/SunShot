/// Linear undo history over a value-type state. Every mutation is named so menus can say "Undo Import Image".
public struct UndoStack<State: Sendable>: Sendable {
    public private(set) var current: State
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private let limit: Int

    private struct Entry: Sendable {
        let name: String
        let state: State
    }

    public init(_ initial: State, limit: Int = SunshotDefaults.undoLimit) {
        current = initial
        self.limit = max(1, limit)
    }

    /// Applies a named change. If `change` throws, nothing is recorded and state is unchanged.
    public mutating func apply(_ name: String, _ change: (inout State) throws -> Void) rethrows {
        var next = current
        try change(&next)
        undoEntries.append(Entry(name: name, state: current))
        if undoEntries.count > limit { undoEntries.removeFirst(undoEntries.count - limit) }
        redoEntries.removeAll()
        current = next
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let entry = undoEntries.popLast() else { return false }
        redoEntries.append(Entry(name: entry.name, state: current))
        current = entry.state
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let entry = redoEntries.popLast() else { return false }
        undoEntries.append(Entry(name: entry.name, state: current))
        current = entry.state
        return true
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var undoActionName: String? { undoEntries.last?.name }
    public var redoActionName: String? { redoEntries.last?.name }
    public var undoCount: Int { undoEntries.count }
    /// Names from oldest to newest.
    public var undoNames: [String] { undoEntries.map(\.name) }
}
