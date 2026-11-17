import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// S11 budgets, in the `RenderPerformanceTests` suite so the gate's release perf stage runs them
/// (only enforced when `SUNSHOT_PERF=1`).
extension RenderPerformanceTests {
    /// `lines` lines of Swift-looking code with a title, line numbers and five highlighted lines.
    static func longSnippet(lines: Int) -> CodeSnippet {
        let block = """
            /// Returns the hour the sun rises for `day`.
            func sunrise(day: Int, latitude: Double) -> Double {
                let angle = Double(day) * 0.017_2 + latitude / 90 // radians
                return 6.0 + sin(angle) * 1.5 + "offset".count
            }

            """
        let code = String(repeating: block, count: lines / 5 + 1).split(
            separator: "\n", omittingEmptySubsequences: false
        )
        .prefix(lines).joined(separator: "\n")
        return CodeSnippet(code: code, highlightedLines: [3, 50, 120, 250, lines - 1], title: "Sunrise.swift")
    }

    private static func medianOfFive(_ body: () throws -> Void) rethrows -> Duration {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<5 { samples.append(try clock.measure(body)) }
        return samples.sorted()[2]
    }

    @Test("[S11-AC19] 500 lines: highlight + 1× render ≤ 150 ms; 300 lines at 2× ≤ 400 ms (median of 5, release)")
    func longSnippetRender() throws {
        let snippet = Self.longSnippet(lines: 500)
        #expect(CodeSnippetLayout.lines(of: snippet.normalizedCode).count == 500)
        let document = EditorDocument(project: Project(), snippet: snippet)
        _ = try Renderer.render(document: document)  // warm-up
        let oneX = try Self.medianOfFive {
            _ = SyntaxHighlighter.tokens(for: snippet.normalizedCode, language: snippet.effectiveLanguage)
            _ = try Renderer.render(document: document)
        }
        // 2× export of 500 lines would exceed the 16384 px export limit; 300 lines is the largest common case.
        let shorter = EditorDocument(project: Project(), snippet: Self.longSnippet(lines: 300))
        let plan = try #require(EditorSession(document: shorter).exportPlan)
        #expect(!plan.isTooLarge)
        let twoX = try Self.medianOfFive { _ = try Renderer.render(document: shorter, scale: 2) }
        print("perf.snippet500_1x.median=\(oneX) perf.snippet500_2x.median=\(twoX)")
        #expect(oneX <= .milliseconds(150), "1× median \(oneX)")
        #expect(twoX <= .milliseconds(400), "2× median \(twoX)")
    }
}
