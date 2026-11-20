import Testing

@testable import SunshotCore

@Suite("Freeze capture marks")
struct FreezeMarksTests {
    private let drag = [AnnotationPoint(x: 10, y: 10), AnnotationPoint(x: 30, y: 20), AnnotationPoint(x: 50, y: 40)]

    @Test("[S19-AC3] arrows and rectangles take start and end; pen and highlighter keep the path")
    func marks() throws {
        let arrow = try #require(FreezeMarks.mark(tool: .arrow, path: drag))
        #expect(arrow.kind == .arrow && arrow.points == [drag[0], drag[2]])
        let box = try #require(FreezeMarks.mark(tool: .rectangle, path: drag))
        #expect(box.kind == .rectangle && box.points.count == 2)
        let pen = try #require(FreezeMarks.mark(tool: .pen, path: drag))
        #expect(pen.points == drag)
        let marker = try #require(FreezeMarks.mark(tool: .highlighter, path: drag))
        #expect(marker.kind == .highlighter && marker.lineWidth > pen.lineWidth)
    }

    @Test("[S19-AC3] a click and the area tool make no mark; keys pick tools")
    func none() {
        #expect(FreezeMarks.mark(tool: .arrow, path: [AnnotationPoint(x: 5, y: 5)]) == nil)
        #expect(
            FreezeMarks.mark(tool: .arrow, path: [AnnotationPoint(x: 5, y: 5), AnnotationPoint(x: 6, y: 5)]) == nil)
        #expect(FreezeMarks.mark(tool: .area, path: drag) == nil)
        #expect(FreezeTool.forShortcut("V") == .area && FreezeTool.forShortcut("a") == .arrow)
        #expect(FreezeTool.forShortcut("z") == nil)
        #expect(Set(FreezeTool.allCases.map(\.shortcut)).count == FreezeTool.allCases.count)
    }
}
