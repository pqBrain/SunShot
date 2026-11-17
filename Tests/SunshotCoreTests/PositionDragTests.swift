import Testing

@testable import SunshotCore

@Suite("Position drag")
struct PositionDragTests {
    /// The mini canvas in the popover.
    static let surface = (width: 200.0, height: 130.0)

    static func drag(halfX: Double = 0.1, halfY: Double = 0.1, startX: Double = 0, startY: Double = 0) -> PositionDrag {
        PositionDrag(
            startX: startX, startY: startY, surfaceWidth: surface.width, surfaceHeight: surface.height,
            halfExtentX: halfX, halfExtentY: halfY)
    }

    @Test("[S6-AC3] dragging 25 % of the width right and 10 % of the height down gives x +0.25, y +0.10")
    func dragMoves() {
        var drag = Self.drag()
        var result = drag.update(translationX: 2, translationY: 1)
        for step in 1...10 {
            let fraction = Double(step) / 10
            result = drag.update(translationX: 50 * fraction, translationY: 13 * fraction)
        }
        #expect(abs(result.x - 0.25) <= 0.005 && abs(result.y - 0.10) <= 0.005, "\(result)")
        #expect(drag.lockedAxis == nil)
    }

    @Test("[S6-AC4] a near-horizontal drag locks to the horizontal axis with a guideline; ⌥ frees it")
    func axisLock() {
        var drag = Self.drag(halfX: 0, halfY: 0)
        _ = drag.update(translationX: 3, translationY: 0)
        #expect(drag.lockedAxis == nil)  // below the 6 px threshold
        let locked = drag.update(translationX: 40, translationY: 5)
        #expect(drag.lockedAxis == .horizontal)
        #expect(locked.y == 0 && abs(locked.x - 0.2) < 1e-12)
        #expect(locked.guides.contains(.axisLock(.horizontal, through: 0)))
        let free = drag.update(translationX: 40, translationY: 26, modifiers: .option)
        #expect(abs(free.y - 0.2) < 1e-12 && abs(free.x - 0.2) < 1e-12)
        #expect(!free.guides.contains { if case .axisLock = $0 { true } else { false } })

        var vertical = Self.drag(halfX: 0, halfY: 0)
        let down = vertical.update(translationX: 1, translationY: 30)
        #expect(vertical.lockedAxis == .vertical && down.x == 0)
        #expect(down.guides.contains(.axisLock(.vertical, through: 0)))

        // A clearly diagonal drag isn't locked.
        var diagonal = Self.drag(halfX: 0, halfY: 0)
        _ = diagonal.update(translationX: 20, translationY: 20)
        #expect(diagonal.lockedAxis == nil)
    }

    @Test("[S6-AC5] centre and edge snapping within 8 px; ⌘ disables it; positions are clamped to ±0.5")
    func snapping() {
        var drag = Self.drag(halfX: 0.2, halfY: 0.2)
        // Diagonal so the axis lock stays out of it.
        let nearCentre = drag.update(translationX: 7, translationY: 30)
        #expect(nearCentre.x == 0 && nearCentre.guides.contains(.centerX))
        let unsnapped = drag.update(translationX: 7, translationY: 30, modifiers: .command)
        #expect(abs(unsnapped.x - 7 / 200) < 1e-12 && unsnapped.guides.isEmpty)

        // Right edge flush at x = 0.5 − 0.2 = 0.3 (60 px); 54 px is within 8 px of it.
        var edge = Self.drag(halfX: 0.2, halfY: 0.2)
        let right = edge.update(translationX: 54, translationY: 40)
        #expect(abs(right.x - 0.3) < 1e-12 && right.guides.contains(.rightEdge))
        let bottom = edge.update(translationX: 30, translationY: 38)
        #expect(abs(bottom.y - 0.3) < 1e-12 && bottom.guides.contains(.bottomEdge))
        let left = edge.update(translationX: -55, translationY: -36)
        #expect(abs(left.x + 0.3) < 1e-12 && abs(left.y + 0.3) < 1e-12)
        #expect(left.guides.contains(.leftEdge) && left.guides.contains(.topEdge))

        var far = Self.drag(halfX: 0, halfY: 0)
        let clamped = far.update(translationX: 500, translationY: -400)
        #expect((clamped.x, clamped.y) == (0.5, -0.5))
        // A locked axis doesn't snap the other one.
        var locked = Self.drag(halfX: 0.2, halfY: 0.2, startX: 0, startY: 0.02)
        let along = locked.update(translationX: 40, translationY: 0)
        #expect(along.y == 0.02)
    }

    @Test("[S6-AC18] keyboard nudges move by 0.01 (⇧ 0.05) and stay in range")
    func keyboard() {
        #expect(abs(PositionDrag.nudged(0, by: 1, large: false) - 0.01) < 1e-12)
        #expect(abs(PositionDrag.nudged(0.1, by: -1, large: true) - 0.05) < 1e-12)
        #expect(PositionDrag.nudged(0.49, by: 1, large: true) == 0.5)
    }

    @Test("[S6-AC9] the tilt pad maps its right edge to tilt Y +30° and its top edge to tilt X +30°")
    func tiltPad() {
        let right = TiltPad.tilt(handleX: 1, handleY: 0)
        #expect(right.tiltY == 30 && right.tiltX == 0)
        let top = TiltPad.tilt(handleX: 0, handleY: -1)
        #expect(top.tiltX == 30 && top.tiltY == 0)
        let beyond = TiltPad.tilt(handleX: 4, handleY: .nan)
        #expect(beyond.tiltY == 30 && beyond.tiltX == 0)
        let handle = TiltPad.handle(for: ContentTransform(tiltX: 15, tiltY: -60))
        #expect(handle.x == -1 && handle.y == -0.5)
    }

    @Test("[S6-AC3] degenerate surfaces and translations don't produce NaN")
    func degenerate() {
        var drag = PositionDrag(
            startX: .nan, startY: 0.9, surfaceWidth: 0, surfaceHeight: .infinity, halfExtentX: .nan, halfExtentY: -1)
        let result = drag.update(translationX: .nan, translationY: .infinity)
        #expect(result.x.isFinite && result.y.isFinite)
        #expect(drag.startY == 0.5)
    }
}
