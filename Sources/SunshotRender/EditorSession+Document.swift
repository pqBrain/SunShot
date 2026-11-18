import SunshotCore

/// Whole-document edits: Start Over. Each is one named undo step; edits that change nothing record
/// nothing.
extension EditorSession {
    public static let startOverActionName = "Start Over"

    /// The document Start Over and File ▸ New produce (the default "Screenshot" template).
    public static var defaultDocument: EditorDocument { EditorDocument() }

    /// Whether Start Over would change anything (the menu item is disabled otherwise).
    public var canStartOver: Bool { canStartOver(to: Self.defaultDocument) }

    /// Whether Start Over to `start` (S12: the default template's document) would change anything.
    public func canStartOver(to start: EditorDocument) -> Bool { document != start }

    /// Resets content and all style to `start` (default: the plain new document) as one undo step. No-op when the
    /// document already is `start`.
    public mutating func startOver(to start: EditorDocument = Self.defaultDocument) {
        history.applyIfChanged(Self.startOverActionName) { $0 = start }
    }
}
