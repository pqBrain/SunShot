import SunshotCore
import Testing

/// Undo keeps its step limit and, with a resource weigher, a memory budget: older steps that hold other images
/// are dropped once the history's distinct images weigh more than the budget.
@Suite("Undo memory budget")
struct UndoBudgetTests {
    /// Each string stands for an image of 100 bytes; equal strings are the same image.
    static func stack(budget: Int) -> UndoStack<[String]> {
        UndoStack([], byteBudget: budget) { state in state.map { (id: $0, bytes: 100) } }
    }

    @Test("steps sharing images cost nothing extra; the first step over budget goes with everything older")
    func trimsOldestOverBudget() {
        var stack = Self.stack(budget: 350)
        stack.apply("A") { $0 = ["a"] }
        stack.apply("A+B") { $0 = ["a", "b"] }
        stack.apply("C") { $0 = ["c"] }
        // c (current) + a, b (one step back) = 300 ≤ 350: every step is kept.
        #expect(stack.undoCount == 3)
        stack.apply("D") { $0 = ["d"] }
        // d + c = 200; the "A+B" state would bring a and b (+200 = 400 > 350): it and older steps go.
        #expect(stack.undoNames == ["D"])
        stack.undo()
        #expect(stack.current == ["c"] && !stack.canUndo)
    }

    @Test("steps that only change style (same images) are never trimmed, even when the current state is over budget")
    func styleStepsStay() {
        var stack = Self.stack(budget: 50)
        stack.apply("Import") { $0 = ["big"] }
        for step in 1...5 { stack.apply("Style \(step)") { $0 = ["big"] } }
        // The empty state before the import and the style steps bring no image the current state lacks: all kept.
        #expect(stack.undoCount == 6)
        stack.beginGesture()
        stack.updateGesture("Drag") { $0 = ["big", "other"] }
        stack.endGesture("Drag")
        #expect(stack.undoNames.last == "Drag")
    }

    @Test("without a weigher only the step limit applies")
    func noWeigher() {
        var stack = UndoStack(0, limit: 3)
        for value in 1...10 { stack.apply("Set") { $0 = value } }
        #expect(stack.undoCount == 3)
    }
}
