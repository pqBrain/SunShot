public import SunshotCore

/// Whole-document edits: Start Over and themes. Each is one named undo step; edits that change nothing record
/// nothing.
extension EditorSession {
    public static let startOverActionName = "Start Over"
    public static let saveThemeActionName = "Save Theme"

    public static func applyThemeActionName(_ name: String) -> String { "Apply Theme \(name)" }

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

    /// Replaces the style with `theme`'s; content, canvas, transform and export options stay.
    /// Throws (nothing changes) if the theme can't be read.
    public mutating func applyTheme(_ theme: Theme) throws {
        let project = try theme.apply(to: document.project)
        history.applyIfChanged(Self.applyThemeActionName(theme.name)) { document in
            document.project = project
            document.theme = theme
        }
    }

    /// Records `theme` as the applied one without changing the style (after Save Theme, whose style already
    /// matches), so the header shows its name. Undoable like every document change.
    public mutating func markThemeSaved(_ theme: Theme) {
        history.applyIfChanged(Self.saveThemeActionName) { $0.theme = theme }
    }
}
