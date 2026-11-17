import Foundation
import Testing

@testable import SunshotCore

@Suite("Annotation interaction")
struct AnnotationInteractionTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    private func context(
        _ tool: AnnotationTool, layer: AnnotationLayer = AnnotationLayer(), selection: Set<UUID> = [],
        style: AnnotationStyle = AnnotationStyle()
    ) -> AnnotationInteraction.Context {
        AnnotationInteraction.Context(
            tool: tool, style: style, layer: layer, selection: selection, longEdge: 1000, tolerance: 3,
            rotateOffset: 20)
    }

    private func drag(_ press: AnnotationPress) throws -> AnnotationDrag {
        guard case .drag(let drag) = press else {
            Issue.record("expected a drag, got \(press)")
            throw CancellationError()
        }
        return drag
    }

    @Test("[S9-AC6] pen: a drag becomes one pen annotation through every sample, duplicates dropped")
    func penDrag() throws {
        let style = AnnotationStyle(color: RGBAColor(rgb: 0xFF0000), lineStyle: .dashed)
        let result = AnnotationInteraction.press(at: point(10, 10), additive: false, in: context(.pen, style: style))
        var drag = try drag(result.press)
        #expect(drag.layer.items.count == 1, "a click alone leaves a dot")
        for sample in [point(20, 12), point(20.2, 12), point(30, 20), point(40, 25)] { drag.update(to: sample) }
        let pen = try #require(drag.layer.items.first)
        #expect(pen.kind == .pen)
        #expect(pen.points == [point(10, 10), point(20, 12), point(30, 20), point(40, 25)])
        #expect(pen.color == RGBAColor(rgb: 0xFF0000))
        #expect(pen.lineStyle == .dashed)
        #expect(pen.lineWidth == 6)
        #expect(drag.actionName == "Draw")
        #expect(drag.base.isEmpty)
    }

    @Test("[S9-AC7] highlighter strokes are three times the pen width")
    func highlighter() throws {
        var drag = try drag(
            AnnotationInteraction.press(at: point(0, 0), additive: false, in: context(.highlighter)).press)
        drag.update(to: point(50, 0))
        #expect(drag.layer.items.first?.lineWidth == 18)
        #expect(drag.actionName == "Highlight")
    }

    @Test("[S9-AC9] [S9-AC10] arrows, rectangles and redactions need a real drag")
    func shapeDrags() throws {
        for (tool, name) in [
            (AnnotationTool.arrow, "Add Arrow"), (.rectangle, "Add Rectangle"), (.redact, "Add Redaction"),
        ] {
            var drag = try drag(
                AnnotationInteraction.press(at: point(100, 100), additive: false, in: context(tool)).press)
            #expect(drag.layer.isEmpty)
            drag.update(to: point(101, 101))
            #expect(drag.layer.isEmpty, "a click without a drag adds nothing")
            drag.update(to: point(40, 160))
            let item = try #require(drag.layer.items.first)
            #expect(item.points == [point(100, 100), point(40, 160)])
            #expect(drag.actionName == name)
        }
        let filled = AnnotationStyle(filled: true)
        var rect = try drag(
            AnnotationInteraction.press(at: point(0, 0), additive: false, in: context(.rectangle, style: filled)).press)
        rect.update(to: point(50, 50))
        #expect(rect.layer.items.first?.filled == true)
        #expect(rect.layer.items.first?.bounds == LayoutRect(x: 0, y: 0, width: 50, height: 50))
    }

    @Test("[S9-AC8] the eraser removes whole objects it passes over, nothing else")
    func eraser() throws {
        let a = Annotation(kind: .pen, points: [point(0, 50), point(30, 50)])
        let b = Annotation(kind: .rectangle, points: [point(60, 40), point(80, 60)], filled: true)
        let c = Annotation(kind: .arrow, points: [point(0, 200), point(100, 200)])
        let layer = AnnotationLayer(items: [a, b, c])
        var drag = try drag(
            AnnotationInteraction.press(at: point(10, 0), additive: false, in: context(.eraser, layer: layer)).press)
        #expect(drag.layer == layer)
        drag.update(to: point(10, 100))  // crosses a
        drag.update(to: point(70, 100))
        drag.update(to: point(70, 0))  // a fast move straight through b
        #expect(drag.layer.items.map(\.id) == [c.id])
        #expect(drag.actionName == "Erase")
    }

    @Test("[S9-AC16] select: click picks the topmost, ⌘-click toggles, empty space clears")
    func selection() {
        let below = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 100)], filled: true)
        let above = Annotation(kind: .rectangle, points: [point(50, 50), point(150, 150)], filled: true)
        let layer = AnnotationLayer(items: [below, above])
        let click = AnnotationInteraction.press(at: point(75, 75), additive: false, in: context(.select, layer: layer))
        #expect(click.selection == [above.id])
        let add = AnnotationInteraction.press(
            at: point(10, 10), additive: true, in: context(.select, layer: layer, selection: [above.id]))
        #expect(add.selection == [above.id, below.id])
        let toggleOff = AnnotationInteraction.press(
            at: point(10, 10), additive: true, in: context(.select, layer: layer, selection: add.selection))
        #expect(toggleOff.selection == [above.id])
        let missAdditive = AnnotationInteraction.press(
            at: point(500, 500), additive: true, in: context(.select, layer: layer, selection: [below.id]))
        #expect(missAdditive.selection == [below.id])
        let miss = AnnotationInteraction.press(
            at: point(500, 500), additive: false, in: context(.select, layer: layer, selection: [below.id]))
        #expect(miss.selection.isEmpty)
        let stale = AnnotationInteraction.press(
            at: point(500, 500), additive: true, in: context(.select, layer: layer, selection: [UUID()]))
        #expect(stale.selection.isEmpty, "ids that no longer exist are dropped")
    }

    @Test("[S9-AC17] move drags the whole selection; resize and rotate drags start on handles")
    func moveResizeRotate() throws {
        let a = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 50)], filled: true)
        let b = Annotation(kind: .pen, points: [point(200, 200), point(220, 210)])
        let layer = AnnotationLayer(items: [a, b])
        let movePress = AnnotationInteraction.press(
            at: point(50, 25), additive: false, in: context(.select, layer: layer, selection: [a.id, b.id]))
        #expect(movePress.selection == [a.id, b.id])
        var move = try drag(movePress.press)
        move.update(to: point(60, 45))
        move.update(to: point(70, 65))
        #expect(move.layer.annotation(a.id)?.bounds.x == 20)
        #expect(move.layer.annotation(b.id)?.points.first == point(220, 240))
        #expect(move.actionName == "Move Annotation")

        var resize = try drag(
            AnnotationInteraction.press(
                at: point(100, 50), additive: false, in: context(.select, layer: layer, selection: [a.id])
            ).press)
        resize.update(to: point(150, 80))
        #expect(resize.layer.annotation(a.id)?.bounds == LayoutRect(x: 0, y: 0, width: 150, height: 80))
        #expect(resize.actionName == "Resize Annotation")

        var rotate = try drag(
            AnnotationInteraction.press(
                at: point(50, -20), additive: false, in: context(.select, layer: layer, selection: [a.id])
            ).press)
        rotate.update(to: point(97, 25), snap: true)
        #expect(rotate.layer.annotation(a.id)?.rotation == 90)
        #expect(rotate.actionName == "Rotate Annotation")
    }

    @Test("[S9-AC9] arrow endpoints move independently")
    func arrowEndpoints() throws {
        let arrow = Annotation(kind: .arrow, points: [point(0, 0), point(100, 0)])
        let layer = AnnotationLayer(items: [arrow])
        var drag = try drag(
            AnnotationInteraction.press(
                at: point(100, 1), additive: false, in: context(.select, layer: layer, selection: [arrow.id])
            ).press)
        drag.update(to: point(80, 60))
        #expect(drag.layer.annotation(arrow.id)?.points == [point(0, 0), point(80, 60)])
        #expect(drag.actionName == "Resize Annotation")
    }

    @Test("[S9-AC11] [S9-AC12] [S9-AC14] text opens an editor; steps and stickers are placed by a click")
    func clickTools() {
        let text = Annotation(kind: .text, points: [point(10, 10), point(110, 40)], text: "Hello")
        let layer = AnnotationLayer(items: [text])
        if case .editText(let at, let id) = AnnotationInteraction.press(
            at: point(50, 20), additive: false, in: context(.text, layer: layer)
        ).press {
            #expect(at == point(10, 10))
            #expect(id == text.id)
        } else {
            Issue.record("expected an existing text to open")
        }
        if case .editText(let at, let id) = AnnotationInteraction.press(
            at: point(300, 300), additive: false, in: context(.text, layer: layer)
        ).press {
            #expect(at == point(300, 300))
            #expect(id == nil)
        } else {
            Issue.record("expected a new text editor")
        }
        for tool in [AnnotationTool.step, .sticker] {
            guard
                case .place(let placed) = AnnotationInteraction.press(
                    at: point(300, 300), additive: false, in: context(tool)
                ).press
            else {
                Issue.record("expected \(tool) to place")
                continue
            }
            #expect(placed.center == point(300, 300))
            #expect(placed.kind == tool.kind)
        }
    }

    @Test("[S9-AC18] duplicate copies on top with an offset and new ids; translate, update and replace")
    func layerEdits() {
        let a = Annotation(kind: .pen, points: [point(0, 0)])
        let b = Annotation(kind: .step, points: [point(0, 0), point(10, 10)])
        var layer = AnnotationLayer(items: [a, b])
        let copies = layer.duplicate([a.id], offset: point(16, 16))
        #expect(layer.items.count == 3)
        #expect(copies.count == 1 && !copies.contains(a.id))
        #expect(layer.items.last?.points == [point(16, 16)])
        layer.translate([b.id], by: point(5, 5))
        #expect(layer.annotation(b.id)?.bounds.x == 5)
        layer.update([b.id]) { $0.color = .black }
        #expect(layer.annotation(b.id)?.color == .black)
        var changed = a
        changed.lineWidth = 20
        layer.replace(changed)
        #expect(layer.annotation(a.id)?.lineWidth == 20)
        layer.replace(Annotation(kind: .pen, points: [point(1, 1)]))
        #expect(layer.items.count == 3, "replacing an unknown id changes nothing")
    }

    @Test("[S9-AC17] drags on annotations that vanished leave the layer unchanged")
    func staleDrags() {
        let layer = AnnotationLayer(items: [Annotation(kind: .pen, points: [point(0, 0)])])
        for mode in [AnnotationDrag.Mode.resize(UUID(), .topLeft), .endpoint(UUID(), 0), .rotate(UUID())] {
            var drag = AnnotationDrag(mode: mode, base: layer, start: point(0, 0), tolerance: 2)
            drag.update(to: point(10, 10))
            #expect(drag.layer == layer)
        }
    }
}
