public import Foundation

/// A named, reusable style: the style subset of a `Project` (never content, canvas size, transform or export
/// options). Stored as one JSON file per theme; the style is kept as JSON keyed by `Theme.fields` so themes
/// saved before a field existed still apply (the missing field takes its default).
public struct Theme: Codable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var name: String
    /// `Theme.fields` key → that field's JSON.
    public var style: [String: JSONValue]

    public init(id: String = UUID().uuidString, name: String, style: [String: JSONValue]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.style = style
    }
}

/// One `Project` property carried by themes.
public struct ThemeField {
    public let key: String
    let read: (Project) throws -> JSONValue
    let write: (JSONValue?, inout Project) throws -> Void

    public init<Value: Codable>(_ key: String, _ path: WritableKeyPath<Project, Value>) {
        self.key = key
        read = { try JSONValue(encoding: $0[keyPath: path]) }
        write = { json, project in
            let fallback = Project()[keyPath: path]
            project[keyPath: path] =
                try json.map { try $0.decodeTolerantly(Value.self, defaults: fallback) } ?? fallback
        }
    }
}

extension Theme {
    /// THE list of style fields a theme carries — the single place to add new style (frame, colour tokens,
    /// fonts, backdrop effects…): one line per `Project` property.
    public static var fields: [ThemeField] {
        [
            ThemeField("backdrop", \.backdropSettings),
            ThemeField("border", \.border),
            ThemeField("shadow", \.shadow),
        ]
    }

    /// The style of `project` as a theme. User images are not carried (themes never hold media): a user-image
    /// backdrop becomes Sunshot's default wallpaper in the theme.
    public static func extract(from project: Project, name: String, id: String = UUID().uuidString) throws -> Theme {
        var source = project
        if case .file = source.backdropSettings.image {
            source.backdropSettings.image = .wallpaper(SunshotDefaults.wallpaper)
        }
        var style: [String: JSONValue] = [:]
        for field in fields { style[field.key] = try field.read(source) }
        return Theme(id: id, name: name, style: style)
    }

    /// `project` with every theme field replaced by this theme's value (default when the theme lacks it).
    /// Everything else (content, canvas, transform, export options…) is untouched.
    public func apply(to project: Project) throws -> Project {
        var result = project
        for field in Self.fields { try field.write(style[field.key], &result) }
        return result
    }

    /// Whether `project`'s style equals this theme's (nil if the theme can't be read).
    public func matches(_ project: Project) -> Bool {
        (try? apply(to: project)) == project
    }

    /// Inspector header: "No Theme", "Ocean" or "Ocean (modified)" (style edited since the theme was applied).
    /// A theme that was deleted from the library reads "No Theme"; a renamed one shows its new name.
    public static func headerTitle(applied: Theme?, project: Project, library: [Theme]) -> String {
        guard let applied, let current = library.first(where: { $0.id == applied.id }) else { return noThemeTitle }
        return current.matches(project) ? current.name : "\(current.name) (modified)"
    }

    public static let noThemeTitle = "No Theme"
}

/// Theme name rules and the file name derived from a name.
public enum ThemeName {
    public static let maxLength = 60

    public enum Problem: Error, Equatable, Sendable {
        case empty
        case tooLong
        /// A theme with this name (case-insensitive) exists; the UI offers "Replace".
        case duplicate(existingID: String)

        public var message: String {
            switch self {
            case .empty: "Enter a name for the theme."
            case .tooLong: "Use \(ThemeName.maxLength) characters or fewer."
            case .duplicate: "A theme with this name already exists."
            }
        }
    }

    /// The trimmed name, or the reason it can't be used. `excluding` skips the theme being renamed.
    public static func validate(
        _ name: String, existing: [Theme], excluding: String? = nil
    ) -> Result<
        String, Problem
    > {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooLong) }
        if let clash = existing.first(where: {
            $0.id != excluding && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return .failure(.duplicate(existingID: clash.id))
        }
        return .success(trimmed)
    }

    /// `ocean.json`: lower-cased, with characters that are illegal or awkward in file names removed (the display
    /// name keeps them). `taken` are file names already used by other themes.
    public static func fileName(for name: String, taken: Set<String> = []) -> String {
        let illegal = Set("/\\:*?\"<>|")
        var base = String(
            name.lowercased().unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init)
                .filter { !illegal.contains($0) })
        base = base.trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "theme" }
        var candidate = "\(base).json"
        var counter = 2
        while taken.contains(candidate) {
            candidate = "\(base)-\(counter).json"
            counter += 1
        }
        return candidate
    }

    /// "Ocean copy", then "Ocean copy 2", … (trimmed to fit the length limit).
    public static func copyName(of name: String, existing: [Theme]) -> String {
        let names = Set(existing.map { $0.name.lowercased() })
        let base = String("\(name) copy".prefix(maxLength - 3))
        var candidate = base
        var counter = 2
        while names.contains(candidate.lowercased()) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }
}
