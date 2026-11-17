/// The starter set of languages Sunshot highlights. Raw values are stored in documents.
public enum CodeLanguage: String, Codable, CaseIterable, Hashable, Sendable {
    case swift
    case javascript
    case typescript
    case python
    case json
    case markup
    case css
    case shell
    case go
    case rust
    case sql
    case plainText = "plain"

    /// Name shown in the language picker.
    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .python: "Python"
        case .json: "JSON"
        case .markup: "HTML / XML"
        case .css: "CSS"
        case .shell: "Shell"
        case .go: "Go"
        case .rust: "Rust"
        case .sql: "SQL"
        case .plainText: "Plain text"
        }
    }
}

/// What a highlighted range of code is. Every code theme has a colour for each kind.
public enum CodeTokenKind: String, Codable, CaseIterable, Hashable, Sendable {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case property
    case tag
    case attribute
    case variable
    case punctuation
}

/// A highlighted range, in UTF-16 code units of the normalised code (what CoreText and AppKit index by).
public struct CodeToken: Hashable, Sendable {
    public let kind: CodeTokenKind
    public let start: Int
    public let length: Int

    public init(kind: CodeTokenKind, start: Int, length: Int) {
        self.kind = kind
        self.start = start
        self.length = length
    }

    public var end: Int { start + length }
    public var range: Range<Int> { start..<end }
}
