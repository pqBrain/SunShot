import Testing

@testable import SunshotCore

@Suite("Code themes")
struct CodeThemeTests {
    @Test("[S11-AC7] at least four Sunshot themes, two light and two dark, unique ids, light default")
    func catalog() {
        let themes = CodeTheme.catalog
        #expect(themes.count >= 4)
        #expect(themes.filter { !$0.isDark }.count >= 2)
        #expect(themes.filter(\.isDark).count >= 2)
        #expect(Set(themes.map(\.id)).count == themes.count)
        #expect(Set(themes.map(\.name)).count == themes.count)
        #expect(CodeTheme.theme(id: CodeTheme.defaultID).isDark == false)
    }

    @Test("[S11-AC7] every theme colours every token kind with readable contrast")
    func contrast() {
        for theme in CodeTheme.catalog {
            for kind in CodeTokenKind.allCases where kind != .plain {
                #expect(theme.tokens[kind] != nil, "\(theme.id) misses \(kind)")
                #expect(
                    CodeTheme.contrast(theme.color(for: kind), theme.background) >= 3, "\(theme.id) \(kind)")
            }
            #expect(theme.color(for: .plain) == theme.foreground)
            #expect(CodeTheme.contrast(theme.foreground, theme.background) >= 4.5, "\(theme.id) text")
            #expect(CodeTheme.contrast(theme.lineNumber, theme.background) >= 2.5, "\(theme.id) line numbers")
            #expect(CodeTheme.contrast(theme.title, theme.background) >= 3, "\(theme.id) title")
            #expect(CodeTheme.contrast(theme.foreground, theme.highlight) >= 4.5, "\(theme.id) highlighted text")
        }
        #expect(abs(CodeTheme.contrast(.black, .white) - 21) < 0.01)
    }
}

@Suite("Language detection")
struct LanguageDetectionTests {
    @Test("[S11-AC6] each starter-language sample is detected", arguments: CodeLanguage.allCases)
    func detects(language: CodeLanguage) {
        #expect(LanguageDetector.detect(CodeFixtures.sample(language)) == language)
    }

    @Test("[S11-AC6] short or ambiguous text is plain text")
    func ambiguous() {
        for text in ["", " ", "x", "hello world", "a = b", "1 + 2", "Dear team, see you tomorrow."] {
            #expect(LanguageDetector.detect(text) == .plainText, "\(text)")
        }
    }

    @Test("[S11-AC6] more detection cases")
    func moreCases() {
        #expect(LanguageDetector.detect("[1, 2, 3]") == .json)
        #expect(LanguageDetector.detect("{ not json }") != .json)
        #expect(LanguageDetector.detect("<?xml version=\"1.0\"?><a/>") == .markup)
        #expect(LanguageDetector.detect("<!DOCTYPE html>\n<html></html>") == .markup)
        #expect(
            LanguageDetector.detect("import SwiftUI\nstruct A: View { var body: some View { Text(\"a\") } }") == .swift)
        #expect(LanguageDetector.detect("$ brew install colima\n$ colima start") == .shell)
        #expect(LanguageDetector.detect("insert into t (a) values (1);") == .sql)
    }

    @Test("[S11-AC6] an explicit language overrides detection")
    func explicitLanguage() {
        let snippet = CodeSnippet(code: CodeFixtures.sample(.python), language: .rust)
        #expect(snippet.effectiveLanguage == .rust)
        #expect(CodeSnippet(code: CodeFixtures.sample(.python)).effectiveLanguage == .python)
    }
}
