/// Dependency-free, single-pass syntax highlighter for the starter languages.
///
/// Works on UTF-16 code units and only ever splits at ASCII characters, so a surrogate pair is never cut.
/// Every input produces sorted, non-overlapping tokens; unterminated strings and comments run to the end of their
/// line (or of the text for block comments and multi-line strings). Plain text gets no tokens.
public enum SyntaxHighlighter {
    public static func tokens(for code: String, language: CodeLanguage) -> [CodeToken] {
        let units = Array(code.utf16)
        switch language {
        case .plainText: return []
        case .markup:
            var scanner = MarkupScanner(units: units)
            return scanner.scan()
        default:
            guard let grammar = CodeGrammar.grammar(for: language) else { return [] }
            var scanner = GrammarScanner(units: units, grammar: grammar)
            return scanner.scan()
        }
    }
}

/// Shared cursor helpers for the scanners.
struct UnitCursor {
    let units: [UInt16]
    var tokens: [CodeToken] = []

    init(units: [UInt16]) { self.units = units }

    var count: Int { units.count }

    func unit(_ index: Int) -> UInt16? { index < units.count && index >= 0 ? units[index] : nil }

    func matches(_ text: String, at index: Int) -> Bool {
        var position = index
        for unit in text.utf16 {
            guard position < units.count, units[position] == unit else { return false }
            position += 1
        }
        return true
    }

    /// Index of the end of the line containing `index` (the newline itself, or the end of the text).
    func lineEnd(from index: Int) -> Int {
        var position = index
        while position < units.count, units[position] != ASCII.newline { position += 1 }
        return position
    }

    /// Index just past `close`, searching from `index`; the end of the text if it never appears.
    func end(of close: String, from index: Int) -> Int {
        var position = index
        while position < units.count {
            if matches(close, at: position) { return position + close.utf16.count }
            position += 1
        }
        return units.count
    }

    /// Index just past the closing `quote` (backslash escapes honoured); stops at a newline unless `multiline`.
    func stringEnd(from index: Int, quote: UInt16, multiline: Bool) -> Int {
        var position = index + 1
        while position < units.count {
            let unit = units[position]
            if unit == ASCII.backslash {
                position += 2
                continue
            }
            if unit == quote { return position + 1 }
            if unit == ASCII.newline, !multiline { return position }
            position += 1
        }
        return units.count
    }

    /// First index at or after `index` that is not a space or tab.
    func skipBlanks(from index: Int) -> Int {
        var position = index
        while let unit = unit(position), unit == ASCII.space || unit == ASCII.tab { position += 1 }
        return position
    }

    mutating func emit(_ kind: CodeTokenKind, _ start: Int, _ end: Int) {
        let end = min(end, units.count)
        guard end > start else { return }
        tokens.append(CodeToken(kind: kind, start: start, length: end - start))
    }

    func text(_ start: Int, _ end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }
}

/// Interprets a `CodeGrammar`.
struct GrammarScanner {
    var cursor: UnitCursor
    let grammar: CodeGrammar
    private var braceDepth = 0

    init(units: [UInt16], grammar: CodeGrammar) {
        cursor = UnitCursor(units: units)
        self.grammar = grammar
    }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        ASCII.isLetter(unit) || unit == ASCII.underscore || unit >= 0x80
            || (grammar.identifierExtras.contains(unit) && unit != ASCII.minus)
    }

    private func isIdentifierPart(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || ASCII.isDigit(unit) || grammar.identifierExtras.contains(unit)
    }

    private func identifierEnd(from index: Int) -> Int {
        var position = index
        while let unit = cursor.unit(position), isIdentifierPart(unit) { position += 1 }
        return position
    }

    mutating func scan() -> [CodeToken] {
        var index = 0
        while index < cursor.count {
            index = step(at: index)
        }
        return cursor.tokens
    }

    /// Scans one token (or skips one character) at `index`; returns the next index (always > `index`).
    private mutating func step(at index: Int) -> Int {
        let unit = cursor.units[index]
        if ASCII.isSpace(unit) { return index + 1 }
        if let end = comment(at: index) { return end }
        if let end = string(at: index) { return end }
        if grammar.css, let end = cssSpecial(unit, at: index) { return end }
        if ASCII.isDigit(unit) || (unit == ASCII.dot && cursor.unit(index + 1).map(ASCII.isDigit) == true) {
            return number(at: index)
        }
        if let end = prefixed(unit, at: index) { return end }
        if isIdentifierStart(unit) { return identifier(at: index) }
        if ASCII.operators.contains(unit) {
            cursor.emit(.punctuation, index, index + 1)
        }
        return index + 1
    }

    private mutating func comment(at index: Int) -> Int? {
        for prefix in grammar.lineComments where cursor.matches(prefix, at: index) {
            // Shell: `#` only starts a comment at a word boundary (`a#b`, `$#` are not comments).
            if prefix == "#", grammar.variablePrefix != nil, let before = cursor.unit(index - 1), !ASCII.isSpace(before)
            {
                continue
            }
            let end = cursor.lineEnd(from: index)
            cursor.emit(.comment, index, end)
            return end
        }
        if let block = grammar.blockComment, cursor.matches(block.open, at: index) {
            let end = cursor.end(of: block.close, from: index + block.open.utf16.count)
            cursor.emit(.comment, index, end)
            return end
        }
        return nil
    }

    private mutating func string(at index: Int) -> Int? {
        let unit = cursor.units[index]
        let end: Int
        if grammar.tripleQuotes, grammar.quotes.contains(unit), cursor.unit(index + 1) == unit,
            cursor.unit(index + 2) == unit
        {
            let fence = cursor.text(index, index + 3)
            end = cursor.end(of: fence, from: index + 3)
        } else if grammar.multilineQuotes.contains(unit) {
            end = cursor.stringEnd(from: index, quote: unit, multiline: true)
        } else if grammar.quotes.contains(unit) {
            if grammar.lifetimes, unit == ASCII.singleQuote, let lifetime = lifetimeEnd(at: index) {
                cursor.emit(.type, index, lifetime)
                return lifetime
            }
            end = cursor.stringEnd(from: index, quote: unit, multiline: false)
        } else {
            return nil
        }
        let isKey = grammar.colonProperties && cursor.unit(cursor.skipBlanks(from: end)) == ASCII.colon
        cursor.emit(isKey ? .property : .string, index, end)
        return end
    }

    /// `'a` (Rust lifetime): a quote, an identifier, and no closing quote right after one character.
    private func lifetimeEnd(at index: Int) -> Int? {
        guard let next = cursor.unit(index + 1), isIdentifierStart(next), cursor.unit(index + 2) != ASCII.singleQuote
        else { return nil }
        return identifierEnd(from: index + 1)
    }

    private mutating func number(at index: Int) -> Int {
        var position = index + 1
        while let unit = cursor.unit(position) {
            if ASCII.isDigit(unit) || ASCII.isLetter(unit) || unit == ASCII.underscore {
                position += 1
            } else if unit == ASCII.dot, cursor.unit(position + 1).map(ASCII.isDigit) == true {
                position += 1
            } else {
                break
            }
        }
        if grammar.css, cursor.unit(position) == 37 { position += 1 }  // 50%
        cursor.emit(.number, index, position)
        return position
    }

    /// `$var` / `${var}`, `@attribute`, `#directive`.
    private mutating func prefixed(_ unit: UInt16, at index: Int) -> Int? {
        guard let next = cursor.unit(index + 1) else { return nil }
        if unit == grammar.variablePrefix {
            if next == ASCII.openBrace {
                let end = cursor.end(of: "}", from: index + 2)
                cursor.emit(.variable, index, end)
                return end
            }
            let end = isIdentifierStart(next) ? identifierEnd(from: index + 1) : index + 2
            cursor.emit(.variable, index, end)
            return end
        }
        if unit == grammar.attributePrefix, isIdentifierStart(next) {
            let end = identifierEnd(from: index + 1)
            cursor.emit(grammar.css ? .keyword : .attribute, index, end)
            return end
        }
        if unit == grammar.directivePrefix, isIdentifierStart(next) || next == ASCII.openBracket {
            let end =
                next == ASCII.openBracket
                ? min(cursor.end(of: "]", from: index + 2), cursor.lineEnd(from: index))
                : identifierEnd(from: index + 1)
            cursor.emit(next == ASCII.openBracket ? .attribute : .keyword, index, end)
            return end
        }
        return nil
    }

    private mutating func identifier(at index: Int) -> Int {
        var end = identifierEnd(from: index)
        let word = cursor.text(index, end)
        let key = grammar.caseInsensitive ? word.lowercased() : word
        let after = cursor.unit(cursor.skipBlanks(from: end))
        let kind: CodeTokenKind?
        if grammar.css {
            if braceDepth == 0 {
                kind = .tag
            } else if after == ASCII.colon {
                kind = .property
            } else {
                kind = grammar.keywords.contains(key) ? .keyword : nil
            }
        } else if grammar.keywords.contains(key) {
            kind = .keyword
        } else if grammar.types.contains(key) {
            kind = .type
        } else if grammar.colonProperties, after == ASCII.colon {
            kind = .property
        } else if grammar.bangMacros, cursor.unit(end) == ASCII.bang {
            end += 1
            kind = .function
        } else if grammar.builtins.contains(key) || after == ASCII.openParen {
            kind = .function
        } else if grammar.capitalizedAreTypes, ASCII.isUpper(cursor.units[index]) {
            kind = .type
        } else {
            kind = nil
        }
        if let kind { cursor.emit(kind, index, end) }
        return end
    }

    /// CSS: brace depth, `.class` / `#id` selectors, `#hex` colours, `!important`.
    private mutating func cssSpecial(_ unit: UInt16, at index: Int) -> Int? {
        switch unit {
        case ASCII.openBrace:
            braceDepth += 1
            return index + 1
        case ASCII.closeBrace:
            braceDepth = max(0, braceDepth - 1)
            return index + 1
        case ASCII.hash, ASCII.dot:
            guard let next = cursor.unit(index + 1), isIdentifierPart(next) else { return nil }
            if unit == ASCII.dot, ASCII.isDigit(next) { return nil }
            let end = identifierEnd(from: index + 1)
            cursor.emit(braceDepth > 0 && unit == ASCII.hash ? .number : .attribute, index, end)
            return end
        default:
            return nil
        }
    }
}
