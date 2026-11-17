/// Linear undo history over a value-type state. Every mutation is named so menus can say "Undo Import Image".
public struct UndoStack<State: Sendable>: Sendable {
    public private(set) var current: State
    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []
    private let limit: Int
    /// State when a continuous gesture (e.g. a slider drag) began; the whole gesture becomes one undo entry.
    private var gestureStart: State?

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

    /// Applies `transform` to the current state and to every undo, redo and gesture-start state, recording
    /// nothing. Used to swap a value that history must not track (S14: the batch item on the canvas).
    public mutating func rewriteAll(_ transform: (inout State) -> Void) {
        transform(&current)
        undoEntries = undoEntries.map { Entry(name: $0.name, state: Self.transformed($0.state, transform)) }
        redoEntries = redoEntries.map { Entry(name: $0.name, state: Self.transformed($0.state, transform)) }
        gestureStart = gestureStart.map { Self.transformed($0, transform) }
    }

    private static func transformed(_ state: State, _ transform: (inout State) -> Void) -> State {
        var copy = state
        transform(&copy)
        return copy
    }

    // MARK: Continuous gestures

    public var isInGesture: Bool { gestureStart != nil }

    /// Starts a gesture. Changes made with `updateGesture` are not recorded until `endGesture`.
    public mutating func beginGesture() {
        if gestureStart == nil { gestureStart = current }
    }

    /// Live change during a gesture (no undo entry). Outside a gesture this behaves like `apply`.
    public mutating func updateGesture(_ name: String, _ change: (inout State) -> Void) {
        guard gestureStart != nil else { return apply(name, change) }
        change(&current)
    }

    /// Ends the gesture, recording a single entry named `name` from the gesture's start state.
    public mutating func endGesture(_ name: String) {
        guard let start = gestureStart else { return }
        gestureStart = nil
        undoEntries.append(Entry(name: name, state: start))
        if undoEntries.count > limit { undoEntries.removeFirst(undoEntries.count - limit) }
        redoEntries.removeAll()
    }

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }
    public var undoActionName: String? { undoEntries.last?.name }
    public var redoActionName: String? { redoEntries.last?.name }
    public var undoCount: Int { undoEntries.count }
    /// Names from oldest to newest.
    public var undoNames: [String] { undoEntries.map(\.name) }
}

extension UndoStack where State: Equatable {
    /// Like `apply`, but records nothing when the change leaves the state equal (e.g. resetting defaults).
    /// Returns whether an entry was recorded.
    @discardableResult
    public mutating func applyIfChanged(_ name: String, _ change: (inout State) -> Void) -> Bool {
        var next = current
        change(&next)
        guard next != current else { return false }
        apply(name) { $0 = next }
        return true
    }

    /// Ends a gesture; records nothing if the state ended where it started.
    public mutating func endGestureIfChanged(_ name: String) {
        guard let start = gestureStart else { return }
        if start == current {
            gestureStart = nil
        } else {
            endGesture(name)
        }
    }
}
