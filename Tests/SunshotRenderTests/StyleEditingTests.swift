import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Border and shadow editing")
struct StyleEditingTests {
    private func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 160, height: 100))
        return session
    }

    @Test("[S2-AC4] typed radius: clamped when numeric, rejected (value kept) otherwise")
    func typedRadius() throws {
        var session = try session()
        let accepted = session.setCornerRadius(text: "10000")
        #expect(accepted)
        #expect(session.project.border.radius == 200)
        let undoCount = session.history.undoCount
        let rejected = !session.setCornerRadius(text: "wide")
        #expect(rejected)
        #expect(session.project.border.radius == 200 && session.history.undoCount == undoCount)
    }

    @Test("[S2-AC6] dragging the radius slider is one undo step; typing 80 matches dragging to 80")
    func sliderGesture() throws {
        var dragged = try session()
        let before = dragged.history.undoCount
        dragged.beginGesture()
        for value in stride(from: 24.0, through: 80, by: 1) { dragged.setCornerRadius(value) }
        dragged.endGesture(EditorSession.cornerRadiusActionName)
        #expect(dragged.history.undoCount == before + 1)
        #expect(dragged.history.undoActionName == EditorSession.cornerRadiusActionName)

        var typed = try session()
        let typedOK = typed.setCornerRadius(text: "80")
        #expect(typedOK)
        #expect(typed.project == dragged.project)
        #expect(try typed.exportPNG() == dragged.exportPNG())
        dragged.undo()
        #expect(dragged.project.border.radius == 24)
    }

    @Test("[S2-AC9] dragging the light handle is one undo step and moves the shadow")
    func lightGesture() throws {
        var session = try session()
        let before = session.history.undoCount
        session.beginGesture()
        for x in [0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6] { session.setLightPosition(UnitOffset(x: x, y: 0)) }
        session.endGesture(EditorSession.lightActionName)
        #expect(session.history.undoCount == before + 1)
        #expect(session.project.shadow.offset.x > 0.59)
    }

    @Test("[S2-AC12] each section reset only touches its own section; resetting defaults is a no-op")
    func resets() throws {
        var session = try session()
        session.setCornerStyle(.round)
        session.setCornerRadius(90)
        session.setShadowStyle(.hug)
        session.setShadowIntensity(.high)
        session.setLightPosition(UnitOffset(x: 0.4, y: 0.2))
        let shadow = session.project.shadow

        session.resetBorder()
        #expect(session.project.border == Border())
        #expect(session.project.shadow == shadow)
        session.setCornerStyle(.round)
        let border = session.project.border
        session.resetShadow()
        #expect(session.project.shadow == Shadow())
        #expect(session.project.border == border)

        session.resetBorder()
        let count = session.history.undoCount
        session.resetBorder()
        session.resetShadow()
        #expect(session.history.undoCount == count)
    }

    @Test("[S2-AC13] every edit is one named undo step; undo-all then redo-all reproduces model and bytes")
    func undoEverything() throws {
        var session = try session()
        let start = session.history.undoCount
        session.setCornerStyle(.round)
        session.setCornerRadius(60)
        session.setShadowStyle(.hug)
        session.setShadowIntensity(.low)
        session.setLightPosition(UnitOffset(x: -0.5, y: -0.5))
        session.resetBorder()
        session.resetShadow()
        #expect(
            Array(session.history.undoNames.dropFirst(start)) == [
                "Change Corner Style", "Change Corner Radius", "Change Shadow Style", "Change Shadow Intensity",
                "Move Light Source", "Reset Border", "Reset Shadow",
            ])
        session.setShadowIntensity(.high)
        let final = session.document
        let bytes = try session.exportPNG()
        while session.history.undoCount > start { session.undo() }
        #expect(session.project == Project())
        while session.history.canRedo { session.redo() }
        #expect(session.document == final)
        #expect(try session.exportPNG() == bytes)
    }

    @Test("[S2-AC14] clearing and importing keeps the border and shadow")
    func styleSurvivesContent() throws {
        var session = try session()
        session.setCornerStyle(.round)
        session.setShadowStyle(.hug)
        let project = session.project
        session.clearContent()
        session.setContent(try SampleContent.image(width: 300, height: 200))
        #expect(session.project == project)
        let expected = try Renderer.render(project: project, content: session.document.content!.image)
        let rendered = try #require(try session.render())
        #expect(try PixelBuffer(rendered).bytes == PixelBuffer(expected).bytes)
    }

    @Test("[S2-AC16] preview and export are byte-identical with a custom border and shadow", arguments: [1.0, 2.0])
    func parity(scale: Double) throws {
        var session = try session()
        session.setCornerStyle(.round)
        session.setCornerRadius(33)
        session.setShadowStyle(.spread)
        session.setShadowIntensity(.high)
        session.setLightPosition(UnitOffset(x: 0.3, y: -0.4))
        let preview = try #require(try session.render(scale: scale))
        let exported = try ImageCodec.decode(session.exportPNG(scale: scale))
        #expect(try PixelBuffer(preview).bytes == PixelBuffer(exported).bytes)
    }
}
