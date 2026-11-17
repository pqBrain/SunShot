import Foundation
import Testing

@testable import SunshotCore

@Suite("Border and shadow model")
struct BorderAndShadowTests {
    @Test("[S2-AC2] border defaults are smooth / 24 px; shadow defaults are spread / medium / (0, 0.35)")
    func defaults() {
        let project = Project()
        #expect(project.border == Border(style: .smooth, radius: 24))
        #expect(project.shadow.style == .spread)
        #expect(project.shadow.intensity == .medium)
        #expect(project.shadow.offset == UnitOffset(x: 0, y: 0.35))
    }

    @Test(
        "[S2-AC4] radius is clamped to 0...200",
        arguments: [(-5.0, 0.0), (0, 0), (1, 1), (200, 200), (201, 200), (10_000, 200)])
    func clamping(input: Double, stored: Double) {
        #expect(Border(style: .round, radius: input).radius == stored)
        var border = Border()
        border.radius = input
        #expect(border.radius == stored)
    }

    @Test("[S2-AC4] typed radius: numbers (optionally with px) parse, anything else is rejected")
    func parsing() {
        #expect(Border.parseRadius("80") == 80)
        #expect(Border.parseRadius(" 12.5 px ") == 12.5)
        #expect(Border.parseRadius("80PX") == 80)
        for bad in ["", "abc", "1e", "nan", "inf", "px"] {
            #expect(Border.parseRadius(bad) == nil, "\(bad)")
        }
        #expect(Border(style: .round, radius: .nan).radius == SunshotDefaults.cornerRadius)
    }

    @Test("[S2-AC5] effective radius is limited to half the shorter side; sharp draws no rounding")
    func effectiveRadius() {
        let big = Border(style: .round, radius: 200)
        #expect(CornerGeometry.effectiveRadius(big, width: 100, height: 60) == 30)
        #expect(big.radius == 200)
        #expect(CornerGeometry.effectiveRadius(Border(style: .smooth, radius: 24), width: 400, height: 300) == 24)
        #expect(CornerGeometry.effectiveRadius(Border(style: .sharp, radius: 40), width: 400, height: 300) == 0)
    }

    @Test("[S2-AC9] moving the light left moves the shadow right, proportionally; centre means no offset")
    func lightHandle() {
        var shadow = Shadow()
        shadow.setLight(at: UnitOffset(x: -0.5, y: 0))
        #expect(shadow.offset == UnitOffset(x: 0.5, y: 0))
        let half = ShadowMetrics.of(shadow)
        shadow.setLight(at: UnitOffset(x: -1, y: 0))
        let full = ShadowMetrics.of(shadow)
        #expect(half.offsetX > 0)
        #expect(abs(full.offsetX - 2 * half.offsetX) < 1e-9)
        shadow.setLight(at: .zero)
        #expect(ShadowMetrics.of(shadow).offsetX == 0 && ShadowMetrics.of(shadow).offsetY == 0)
        #expect(shadow.lightPosition == .zero)
    }

    @Test("[S2-AC9] the handle is clamped inside the circle (length ≤ 1)")
    func handleClamp() {
        let far = UnitOffset(x: 3, y: 4)
        #expect(abs(hypot(far.x, far.y) - 1) < 1e-9)
        #expect(abs(far.x - 0.6) < 1e-9 && abs(far.y - 0.8) < 1e-9)
        #expect(UnitOffset(x: .nan, y: .infinity) == .zero)
        #expect(UnitOffset(x: 0.3, y: 0.4) == UnitOffset(x: 0.3, y: 0.4))
    }

    @Test("[S2-AC11] keyboard steps are 0.02 and 0.1 and stay inside the circle")
    func keyboardSteps() {
        #expect(UnitOffset.keyboardStep == 0.02)
        #expect(UnitOffset.largeKeyboardStep == 0.1)
        let moved = UnitOffset.zero.nudged(dx: UnitOffset.keyboardStep, dy: 0)
        #expect(abs(moved.x - 0.02) < 1e-9)
        var edge = UnitOffset(x: 1, y: 0)
        for _ in 0..<5 { edge = edge.nudged(dx: 0, dy: UnitOffset.largeKeyboardStep) }
        #expect(hypot(edge.x, edge.y) <= 1 + 1e-9)
    }

    @Test("[S2-AC7] spread blurs more than hug; peak opacity orders low < medium < high; hug stays within 12 px")
    func metrics() {
        #expect(ShadowMetrics.of(Shadow(style: .none)) == .none)
        for intensity in ShadowIntensity.allCases {
            let spread = ShadowMetrics.of(Shadow(style: .spread, intensity: intensity))
            let hug = ShadowMetrics.of(Shadow(style: .hug, intensity: intensity, offset: UnitOffset(x: 0, y: 1)))
            #expect(spread.blur > hug.blur)
            #expect(hug.extent <= ShadowMetrics.hugMaxExtent)
        }
        for style in [ShadowStyle.spread, .hug] {
            let opacities = ShadowIntensity.allCases.map {
                ShadowMetrics.of(Shadow(style: style, intensity: $0)).opacity
            }
            #expect(opacities == opacities.sorted() && Set(opacities).count == 3)
        }
        // Spread must fit inside the default padding so it is never clipped.
        let worst = ShadowMetrics.of(Shadow(style: .spread, intensity: .high, offset: UnitOffset(x: 0, y: 1)))
        #expect(worst.extent < SunshotDefaults.padding)
    }

    @Test("[S2-AC10] shadow metrics at 2× are exactly twice the 1× values")
    func scaling() {
        let one = ShadowMetrics.of(Shadow())
        let two = one.scaled(by: 2)
        #expect(two.blur == one.blur * 2 && two.offsetX == one.offsetX * 2 && two.offsetY == one.offsetY * 2)
        #expect(two.opacity == one.opacity)
    }

    @Test("[S2-AC6] a gesture records exactly one undo step, and none if nothing changed")
    func gestureUndo() {
        var stack = UndoStack(0)
        stack.beginGesture()
        #expect(stack.isInGesture)
        for value in 1...20 { stack.updateGesture("Drag") { $0 = value } }
        #expect(!stack.canUndo)
        stack.endGestureIfChanged("Drag")
        #expect(stack.current == 20 && stack.undoActionName == "Drag")
        stack.undo()
        #expect(stack.current == 0 && !stack.canUndo)

        stack.beginGesture()
        stack.updateGesture("Drag") { $0 = 5 }
        stack.updateGesture("Drag") { $0 = 0 }
        stack.endGestureIfChanged("Drag")
        #expect(!stack.canUndo, "a drag that ends where it started adds nothing")
        #expect(!stack.isInGesture)
    }

    @Test("[S2-AC12] a no-op change adds no undo entry")
    func noOp() {
        var stack = UndoStack(1)
        #expect(!stack.applyIfChanged("Same") { $0 = 1 })
        #expect(!stack.canUndo)
        #expect(stack.applyIfChanged("Other") { $0 = 2 })
        #expect(stack.canUndo)
    }

    @Test("[S2-AC13] border and shadow round-trip through Codable")
    func coding() throws {
        let project = Project(
            border: Border(style: .round, radius: 90),
            shadow: Shadow(style: .hug, intensity: .high, offset: UnitOffset(x: 0.2, y: -0.4)))
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data) == project)
    }
}
