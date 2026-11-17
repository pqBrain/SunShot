import Foundation
import Testing

@testable import SunshotCore

@Suite("Syntax highlighter")
struct SyntaxHighlighterTests {
    /// Kind of the token covering the first occurrence of `fragment` (nil = no token there, i.e. plain).
    private func kind(of fragment: String, in code: String, _ language: CodeLanguage) -> CodeTokenKind? {
        guard let range = code.range(of: fragment) else {
            Issue.record("fragment \(fragment) not in sample")
            return nil
        }
        let start = code.utf16.distance(from: code.utf16.startIndex, to: range.lowerBound)
        let tokens = SyntaxHighlighter.tokens(for: code, language: language)
        return tokens.first { $0.range.contains(start) }?.kind
    }

    private func expect(_ language: CodeLanguage, _ expected: [(String, CodeTokenKind?)]) {
        let code = CodeFixtures.sample(language)
        for (fragment, kind) in expected {
            #expect(self.kind(of: fragment, in: code, language) == kind, "\(language) \(fragment)")
        }
    }

    @Test("[S11-AC4] Swift tokens")
    func swift() {
        expect(
            .swift,
            [
                ("// Sunshot", .comment), ("struct", .keyword), ("Sunrise", .type), ("let", .keyword), ("6", .number),
                ("greet", .function), ("String", .type), ("\"Good", .string), ("hour", nil),
            ])
    }

    @Test("[S11-AC4] JavaScript tokens")
    func javascript() {
        expect(
            .javascript,
            [
                ("// Fetch", .comment), ("const", .keyword), ("\"Lisbon\"", .string), ("forecast(days)", .function),
                ("`/api", .string), ("console", .function), ("3)", .number), ("===", .punctuation),
                ("undefined", .keyword),
            ])
    }

    @Test("[S11-AC4] TypeScript tokens")
    func typescript() {
        expect(
            .typescript,
            [
                ("interface", .keyword), ("Sunrise", .type), ("number", .type), ("\"light\"", .string),
                ("type", .keyword), ("shift", .function), ("6,", .number),
            ])
    }

    @Test("[S11-AC4] Python tokens")
    func python() {
        expect(
            .python,
            [
                ("# Count", .comment), ("def", .keyword), ("sunny_days", .function), ("for", .keyword),
                ("0.5", .number), ("print", .function), ("in readings", .keyword), ("total", nil),
            ])
    }

    @Test("[S11-AC4] JSON tokens")
    func json() {
        expect(
            .json,
            [
                ("\"name\"", .property), ("\"Sunshot\"", .string), ("2", .number), ("true", .keyword),
                ("null", .keyword), ("\"code\"", .string),
            ])
    }

    @Test("[S11-AC4] HTML / XML tokens")
    func markup() {
        expect(
            .markup,
            [
                ("<!--", .comment), ("div", .tag), ("class", .attribute), ("\"card\"", .string), ("'hero'", .string),
                ("&amp;", .keyword), ("Hello", nil), ("img", .tag), ("/>", .punctuation),
            ])
    }

    @Test("[S11-AC4] CSS tokens")
    func css() {
        expect(
            .css,
            [
                ("/* Card", .comment), (".card", .attribute), ("color", .property), ("#1d4ed8", .number),
                ("12px", .number), ("@media", .keyword), ("600px", .number), ("flex", nil),
            ])
    }

    @Test("[S11-AC4] Shell tokens")
    func shell() {
        expect(
            .shell,
            [
                ("#!/bin/bash", .comment), ("# Build", .comment), ("if", .keyword), ("echo", .function),
                ("\"Copying", .string), ("$HOME", .variable), ("fi", .keyword), ("\"sunshot\"", .string),
            ])
    }

    @Test("[S11-AC4] Go tokens")
    func go() {
        expect(
            .go,
            [
                ("package", .keyword), ("\"fmt\"", .string), ("// Greet", .comment), ("main()", .function),
                ("6", .number), ("Println", .function), ("\"Good", .string), (":=", .punctuation),
            ])
    }

    @Test("[S11-AC4] Rust tokens")
    func rust() {
        expect(
            .rust,
            [
                ("// A sunrise", .comment), ("#[derive", .attribute), ("struct", .keyword), ("'a>", .type),
                ("str }", .type), ("fn", .keyword), ("mut", .keyword), ("u32", .type), ("println!", .function),
                ("\"Good", .string),
            ])
    }

    @Test("[S11-AC4] SQL tokens, keywords in any case")
    func sql() {
        expect(
            .sql,
            [
                ("-- Sunny", .comment), ("SELECT", .keyword), ("COUNT", .function), ("FROM", .keyword),
                ("0.5", .number), ("GROUP", .keyword), ("DESC", .keyword), ("readings", nil),
            ])
        let lower = SyntaxHighlighter.tokens(for: "select 1 from t", language: .sql)
        #expect(lower.first?.kind == .keyword)
    }

    @Test("[S11-AC4] plain text has no coloured tokens")
    func plain() {
        #expect(SyntaxHighlighter.tokens(for: CodeFixtures.sample(.swift), language: .plainText).isEmpty)
        #expect(SyntaxHighlighter.tokens(for: CodeFixtures.sample(.plainText), language: .plainText).isEmpty)
    }

    // MARK: Robustness

    private func checkInvariants(_ code: String, _ language: CodeLanguage) {
        let units = Array(code.utf16)
        let tokens = SyntaxHighlighter.tokens(for: code, language: language)
        var previousEnd = 0
        for token in tokens {
            #expect(token.length > 0)
            #expect(token.start >= previousEnd, "overlap in \(language)")
            #expect(token.end <= units.count)
            if token.start < units.count { #expect(!UTF16.isTrailSurrogate(units[token.start])) }
            if token.end < units.count { #expect(!UTF16.isTrailSurrogate(units[token.end])) }
            previousEnd = token.end
        }
    }

    @Test("[S11-AC5] tokens are sorted, disjoint, in range and never split a surrogate pair (fuzzed)")
    func fuzz() {
        let alphabet = Array("ab Z9_.\"'`/*#$@{}()[]<>!-=:;\\\n\t\r😀日本&?%,")
        var state: UInt32 = 2026
        for language in CodeLanguage.allCases {
            for round in 0..<60 {
                var text = ""
                for _ in 0..<(round * 7 % 90 + 1) {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    text.append(alphabet[Int(state >> 16) % alphabet.count])
                }
                checkInvariants(text, language)
            }
        }
    }

    @Test("[S11-AC5] edge inputs: empty, unterminated, emoji, CRLF, long lines")
    func edgeInputs() {
        let inputs = [
            "", "\"never closed\nlet x = 1", "/* never closed", "'''open", "`template ${", "<div class=\"x",
            "<!-- open", "😀 = \"日本\" // 😀", "let a = 1\r\nlet b = 2\r\n", String(repeating: "x = 1; ", count: 5000),
            "$", "@", "#", "'", "\\", "0x", ".5", "#[", "${",
        ]
        for language in CodeLanguage.allCases {
            for input in inputs { checkInvariants(input, language) }
        }
        let swift = SyntaxHighlighter.tokens(for: "\"never closed\nlet x", language: .swift)
        #expect(swift.first == CodeToken(kind: .string, start: 0, length: 13))
        #expect(swift.contains { $0.kind == .keyword })
        let comment = SyntaxHighlighter.tokens(for: "a /* never closed\nmore", language: .javascript)
        #expect(comment.last == CodeToken(kind: .comment, start: 2, length: 20))
        #expect(SyntaxHighlighter.tokens(for: "", language: .swift).isEmpty)
    }
}
