import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Annotation editing")
struct AnnotationEditingTests {
    private func point(_ x: Double, _ y: Double) -> AnnotationPoint { AnnotationPoint(x: x, y: y) }

    private func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try Fixtures.solid(width: 2000, height: 1000))
        return session
    }

    @Test("[S9-AC18] add, duplicate, delete and clear are one undo entry each; undo restores exactly")
    func commands() throws {
        var session = try session()
        let pen = Annotation(kind: .pen, points: [point(10, 10), point(50, 50)])
        session.addAnnotation(pen)
        #expect(session.history.undoActionName == "Draw")
        let before = session.annotations
        let copies = session.duplicateAnnotations([pen.id])
        #expect(session.history.undoActionName == "Duplicate Annotation")
        let copyID = try #require(copies.first)
        let copy = try #require(session.annotations.annotation(copyID))
        #expect(copy.points.first == point(42, 42), "offset 16 px × (2000 / 1000)")
        session.undo()
        #expect(session.annotations == before)
        session.redo()
        session.deleteAnnotations([pen.id])
        #expect(session.history.undoActionName == "Delete Annotation")
        #expect(session.annotations.items.map(\.id) == copies.sorted { $0.uuidString < $1.uuidString })
        session.clearAnnotations()
        #expect(session.history.undoActionName == "Clear Annotations")
        #expect(session.project.annotationLayer == nil)
        let count = session.history.undoCount
        session.clearAnnotations()
        session.deleteAnnotations([UUID()])
        #expect(session.duplicateAnnotations([]).isEmpty)
        #expect(session.history.undoCount == count, "no-op edits record nothing")
        session.undo()
        #expect(session.annotations.items.count == 1)
    }

    @Test("[S9-AC17] a drag is one undo entry; a drag that ends where it began records nothing")
    func gestures() throws {
        var session = try session()
        let rect = Annotation(kind: .rectangle, points: [point(0, 0), point(100, 100)], filled: true)
        session.addAnnotation(rect)
        let count = session.history.undoCount
        var drag = AnnotationDrag(mode: .move([rect.id]), base: session.annotations, start: point(50, 50), tolerance: 2)
        session.beginGesture()
        for x in stride(from: 51.0, through: 90, by: 3) {
            drag.update(to: point(x, 50))
            session.setAnnotations(drag.layer, actionName: drag.actionName)
        }
        session.endGesture(drag.actionName)
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == "Move Annotation")
        #expect(session.annotations.annotation(rect.id)?.bounds.x == 40)

        session.beginGesture()
        drag = AnnotationDrag(mode: .move([rect.id]), base: session.annotations, start: point(50, 50), tolerance: 2)
        drag.update(to: point(50, 50))
        session.setAnnotations(drag.layer, actionName: drag.actionName)
        session.endGesture(drag.actionName)
        #expect(session.history.undoCount == count + 1)
        session.undo()
        #expect(session.annotations.annotation(rect.id)?.bounds.x == 0)
    }

    @Test("[S9-AC11] committing text adds, edits or removes a text annotation")
    func text() throws {
        var session = try session()
        let style = AnnotationStyle()
        #expect(session.commitText("   ", at: point(10, 10), id: nil, style: style) == nil)
        #expect(session.annotations.isEmpty)
        let added = session.commitText("Hello", at: point(10, 10), id: nil, style: style)
        let id = try #require(added)
        #expect(session.history.undoActionName == "Add Text")
        #expect(session.annotations.annotation(id)?.fontSize == 48, "M on a 2000 px image")
        #expect(session.commitText("Hello\nworld", at: point(0, 0), id: id, style: style) == id)
        #expect(session.history.undoActionName == "Edit Text")
        #expect(session.annotations.annotation(id)?.text == "Hello\nworld")
        #expect(session.annotations.annotation(id)?.bounds.x == 10)
        #expect(session.commitText("", at: point(0, 0), id: id, style: style) == nil)
        #expect(session.annotations.isEmpty)
        #expect(session.history.undoActionName == "Delete Annotation")
    }

    @Test("[S9-AC15] restyling a selection and changing the step format are single entries")
    func restyle() throws {
        var session = try session()
        let a = Annotation(kind: .pen, points: [point(0, 0)])
        let b = Annotation(kind: .arrow, points: [point(0, 0), point(9, 9)])
        session.addAnnotation(a)
        session.addAnnotation(b)
        let count = session.history.undoCount
        session.restyleAnnotations([a.id, b.id]) { $0.lineStyle = .dotted }
        #expect(session.annotations.items.allSatisfy { $0.lineStyle == .dotted })
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == "Change Annotation Style")
        session.restyleAnnotations([]) { $0.lineStyle = .solid }
        #expect(session.history.undoCount == count + 1)
        session.setStepFormat(.letters)
        #expect(session.annotations.stepFormat == .letters)
        #expect(session.history.undoActionName == "Change Step Format")
        #expect(EditorSession().contentLongEdge == 1000)
    }
}
