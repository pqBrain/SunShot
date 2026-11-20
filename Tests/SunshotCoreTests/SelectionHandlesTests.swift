import Testing

@testable import SunshotCore

@Suite("Capture selection handles")
struct SelectionHandlesTests {
    private let rect = LayoutRect(x: 100, y: 100, width: 200, height: 100)

    @Test("[S19-AC6] edges and corners are found within the tolerance; the middle is not a grip")
    func hit() {
        #expect(SelectionHandle.hit(rect: rect, point: (101, 99)) == .topLeft)
        #expect(SelectionHandle.hit(rect: rect, point: (299, 201)) == .bottomRight)
        #expect(SelectionHandle.hit(rect: rect, point: (200, 103)) == .top)
        #expect(SelectionHandle.hit(rect: rect, point: (297, 150)) == .right)
        #expect(SelectionHandle.hit(rect: rect, point: (96, 150)) == .left)
        #expect(SelectionHandle.hit(rect: rect, point: (200, 150)) == nil)
        #expect(SelectionHandle.hit(rect: rect, point: (50, 50)) == nil)
    }

    @Test("[S19-AC6] dragging a grip moves only its edges")
    func resize() {
        let right = SelectionHandle.right.resized(rect, to: (350, 999), displayWidth: 1000, displayHeight: 800)
        #expect(right == LayoutRect(x: 100, y: 100, width: 250, height: 100))
        let corner = SelectionHandle.topLeft.resized(rect, to: (50, 20), displayWidth: 1000, displayHeight: 800)
        #expect(corner == LayoutRect(x: 50, y: 20, width: 250, height: 180))
    }

    @Test("[S19-AC6] a selection stays on the display and never flips or shrinks below the minimum")
    func limits() {
        let outside = SelectionHandle.bottomRight.resized(
            rect, to: (5000, 5000), displayWidth: 1000, displayHeight: 800)
        #expect(outside == LayoutRect(x: 100, y: 100, width: 900, height: 700))
        let crossed = SelectionHandle.left.resized(rect, to: (900, 0), displayWidth: 1000, displayHeight: 800)
        #expect(crossed.width == AreaSelection.minimumSide && crossed.x + crossed.width == 300)
        let off = SelectionHandle.topLeft.resized(rect, to: (-40, -40), displayWidth: 1000, displayHeight: 800)
        #expect(off.x == 0 && off.y == 0)
    }
}
