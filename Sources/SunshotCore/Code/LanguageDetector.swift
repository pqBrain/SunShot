import Foundation

/// Guesses the language of a snippet from weighted textual signals. Cheap (substring checks on at most the first
/// `sampleLimit` characters); text that doesn't clearly look like one language is Plain text.
public enum LanguageDetector {
    /// Characters inspected (detection runs on every keystroke).
    static let sampleLimit = 4000
    /// The best language must score at least this much, and beat the runner-up.
    static let threshold = 3

    private struct Signal {
        let text: String
        let weight: Int
        var lineStart = false
    }

    private static func signals(_ pairs: [(String, Int)], lineStart: Bool = false) -> [Signal] {
        pairs.map { Signal(text: $0.0, weight: $0.1, lineStart: lineStart) }
    }

    private static let table: [(CodeLanguage, [Signal])] = [
        (
            .swift,
            signals([
                ("func ", 2), ("guard ", 3), ("import SwiftUI", 5), ("import Foundation", 5), ("@State", 4),
                ("-> ", 1), ("struct ", 1), ("extension ", 2), ("let ", 1), ("var body: some View", 5),
                ("\\(", 2), ("if let ", 3), ("protocol ", 2), (": View", 3), ("@MainActor", 4), ("?? ", 1),
            ])
        ),
        (
            .javascript,
            signals([
                ("function ", 2), ("const ", 2), ("=> ", 2), ("console.log", 4), ("require(", 4), ("document.", 3),
                ("===", 3), ("module.exports", 5), ("export default", 3), ("let ", 1), ("async ", 1),
            ])
        ),
        (
            .typescript,
            signals([
                ("interface ", 3), (": string", 4), (": number", 4), (": boolean", 4), ("type ", 1),
                ("as const", 4), ("implements ", 2), ("readonly ", 2), ("<T>", 2), ("export type ", 4),
                ("const ", 1), ("=> ", 1), ("import type ", 5),
            ])
        ),
        (
            .python,
            signals([
                ("def ", 3), ("elif ", 4), ("self.", 2), ("None", 2), (".append(", 2), ("__init__", 4),
                ("import ", 1), ("from ", 1), ("True", 1), ("False", 1), ("lambda ", 2), (" in range(", 4),
                ("if __name__", 5),
            ]) + signals([("def ", 2), ("class ", 1), ("from ", 2), ("@", 1)], lineStart: true)
        ),
        (
            .css,
            signals([
                ("px;", 3), ("color:", 2), ("margin:", 3), ("padding:", 3), ("display:", 3), ("@media", 4),
                ("font-", 2), ("border:", 2), ("rem;", 3), ("background:", 2), ("!important", 3),
            ])
        ),
        (
            .shell,
            signals([
                ("#!/bin/", 6), ("#!/usr/bin/env bash", 6), ("$ ", 1), ("echo ", 2), ("fi\n", 3), ("done", 1),
                ("then", 1), ("export ", 1), ("${", 2), ("&& ", 1), ("| grep", 3), ("sudo ", 3),
            ]) + signals([("$ ", 2), ("cd ", 2), ("brew ", 4), ("npm ", 3), ("git ", 3), ("fi", 2)], lineStart: true)
        ),
        (
            .go,
            signals([
                ("package ", 3), ("func (", 4), (":= ", 3), ("fmt.", 4), ("import (", 4), ("chan ", 3),
                ("go func", 4), ("err != nil", 5), ("defer ", 1),
            ])
        ),
        (
            .rust,
            signals([
                ("fn ", 3), ("let mut ", 5), ("impl ", 3), ("pub fn", 4), ("use std", 5), ("println!", 5),
                ("&str", 4), ("::", 1), ("-> ", 1), ("match ", 1), ("Vec<", 3), ("Option<", 2), ("#[derive", 5),
            ])
        ),
    ]

    /// SQL keywords are matched case-insensitively.
    private static let sqlSignals: [(String, Int)] = [
        ("select ", 2), (" from ", 2), ("where ", 2), ("insert into", 5), ("create table", 5), ("update ", 1),
        (" set ", 1), ("group by", 4), ("order by", 4), ("join ", 2), ("delete from", 5), ("values (", 3),
    ]

    public static func detect(_ code: String) -> CodeLanguage {
        let sample = String(code.prefix(sampleLimit))
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return .plainText }
        if looksLikeJSON(code) { return .json }
        if looksLikeMarkup(trimmed) { return .markup }
        var scores = scored(sample)
        // TypeScript is JavaScript plus types: count JavaScript signals towards it once it has its own.
        if let typeScript = scores[.typescript], typeScript >= threshold {
            scores[.typescript] = typeScript + (scores[.javascript] ?? 0)
        }
        let ranked = scores.sorted { $0.value != $1.value ? $0.value > $1.value : order($0.key) < order($1.key) }
        guard let best = ranked.first, best.value >= threshold else { return .plainText }
        if ranked.count > 1, ranked[1].value == best.value { return .plainText }
        return best.key
    }

    private static func scored(_ sample: String) -> [CodeLanguage: Int] {
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.drop { $0 == " " || $0 == "\t" } }
        var scores: [CodeLanguage: Int] = [:]
        for (language, signals) in table {
            var score = 0
            for signal in signals {
                if signal.lineStart {
                    if lines.contains(where: { $0.hasPrefix(signal.text) }) { score += signal.weight }
                } else if sample.contains(signal.text) {
                    score += signal.weight
                }
            }
            if score > 0 { scores[language] = score }
        }
        let lowered = sample.lowercased()
        let sql = sqlSignals.reduce(0) { $0 + (lowered.contains($1.0) ? $1.1 : 0) }
        if sql > 0 { scores[.sql] = sql }
        return scores
    }

    private static func order(_ language: CodeLanguage) -> Int {
        CodeLanguage.allCases.firstIndex(of: language) ?? Int.max
    }

    private static func looksLikeJSON(_ code: String) -> Bool {
        guard code.utf8.count <= 1_000_000 else { return false }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[",
            let last = trimmed.last, last == "}" || last == "]",
            let data = trimmed.data(using: .utf8)
        else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private static func looksLikeMarkup(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("<") else { return false }
        return trimmed.hasPrefix("<?xml") || trimmed.lowercased().hasPrefix("<!doctype") || trimmed.contains("</")
            || trimmed.contains("/>")
    }
}
