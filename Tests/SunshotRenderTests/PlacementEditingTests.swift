import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Placement editing")
struct PlacementEditingTests {
    static func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 400, height: 250))
        return session
    }

    static let tabletop = LayoutPreset(
        id: "tabletop", name: "Tabletop", transform: ContentTransform(y: 0.04, zoom: 96, tiltX: 34))

    @Test("[S6-AC3] a whole position drag is one undo entry \"Move Content\"")
    func dragIsOneStep() throws {
        var session = try Self.session()
        var drag = session.positionDrag(surfaceWidth: 200, surfaceHeight: 130)
        #expect(abs(drag.halfExtentX - 200.0 / 528) < 1e-9)
        session.beginGesture()
        for step in 1...10 {
            let result = drag.update(translationX: 5 * Double(step), translationY: 1.3 * Double(step))
            session.moveContent(x: result.x, y: result.y)
        }
        session.endGesture(EditorSession.moveContentActionName)
        #expect(abs(session.contentTransform.x - 0.25) <= 0.005 && abs(session.contentTransform.y - 0.10) <= 0.005)
        #expect(session.history.undoNames == [EditorSession.importActionName, "Move Content"])
        session.undo()
        #expect(session.contentTransform.isIdentity)
    }

    @Test("[S6-AC6] [S6-AC7] typed zoom and rotation are parsed, clamped and normalised; junk is refused")
    func typedValues() throws {
        var session = try Self.session()
        let accepted = [session.setZoom(text: " 150.4 % ")]
        #expect(session.contentTransform.zoom == 150)
        let rotated = session.setRotation(text: "270°")
        #expect(session.contentTransform.rotation == -90)
        let refused = [session.setZoom(text: "big"), session.setRotation(text: ""), session.setZoom(text: "inf")]
        #expect(accepted == [true] && rotated && refused == [false, false, false])
        session.setZoom(401)
        #expect(session.contentTransform.zoom == 400)
        #expect(session.history.undoNames.suffix(3) == ["Change Zoom", "Rotate Content", "Change Zoom"])
    }

    @Test("[S6-AC9] a tilt drag is one undo entry \"Tilt Content\"")
    func tiltIsOneStep() throws {
        var session = try Self.session()
        session.beginGesture()
        for step in 1...6 {
            let tilt = TiltPad.tilt(handleX: Double(step) / 6, handleY: 0)
            session.setTilt(x: tilt.tiltX, y: tilt.tiltY)
        }
        session.endGesture(EditorSession.tiltActionName)
        #expect(session.contentTransform.tiltY == 30)
        #expect(session.history.undoActionName == "Tilt Content")
        #expect(session.history.undoCount == 2)
    }

    @Test("[S6-AC12] Reset Position returns all six values to identity as one entry; no entry when already identity")
    func reset() throws {
        var session = try Self.session()
        session.applyLayoutPreset(Self.tabletop)
        session.setRotation(12)
        session.resetPosition()
        #expect(session.contentTransform.isIdentity)
        #expect(session.layoutPresetID == nil)
        #expect(session.history.undoActionName == "Reset Position")
        let count = session.history.undoCount
        session.resetPosition()
        #expect(session.history.undoCount == count)
        // Reset of an applied preset clears its selection.
        session.applyLayoutPreset(Self.tabletop)
        session.resetPosition()
        #expect(session.layoutPresetID == nil)
    }

    @Test("[S6-AC15] applying a preset sets its exact transform and selection; manual edits clear it; undo restores")
    func applyPreset() throws {
        var session = try Self.session()
        session.moveContent(x: 0.1, y: 0)
        session.applyLayoutPreset(Self.tabletop)
        #expect(session.contentTransform == Self.tabletop.transform)
        #expect(session.layoutPresetID == "tabletop")
        #expect(session.history.undoActionName == "Apply Layout Tabletop")
        let count = session.history.undoCount
        session.applyLayoutPreset(Self.tabletop)
        #expect(session.history.undoCount == count)  // applying the same layout again changes nothing

        session.setZoom(110)
        #expect(session.layoutPresetID == nil)
        session.undo()
        #expect(session.layoutPresetID == "tabletop" && session.contentTransform == Self.tabletop.transform)
        session.undo()
        #expect(session.layoutPresetID == nil && session.contentTransform == ContentTransform(x: 0.1))
        // A no-op edit keeps the selection.
        session.redo()
        session.setZoom(96)
        #expect(session.layoutPresetID == "tabletop")
    }

    @Test("[S6-AC19] each transform edit is one entry; undo-all → identity, redo-all reproduces; survives re-import")
    func undoAll() throws {
        var session = try Self.session()
        session.moveContent(x: 0.2, y: -0.1)
        session.setTilt(x: 10, y: -20)
        session.setZoom(140)
        session.setRotation(-15)
        session.resetPosition()
        session.applyLayoutPreset(Self.tabletop)
        #expect(
            session.history.undoNames == [
                "Import Image", "Move Content", "Tilt Content", "Change Zoom", "Rotate Content", "Reset Position",
                "Apply Layout Tabletop",
            ])
        var states: [EditorDocument] = [session.document]
        for _ in 0..<6 {
            session.undo()
            states.append(session.document)
        }
        #expect(session.contentTransform.isIdentity)
        for expected in states.reversed().dropFirst() {
            session.redo()
            #expect(session.document.project == expected.project)
        }
        session.clearContent()
        #expect(session.contentTransform == Self.tabletop.transform)
        #expect(session.contentProjection == nil)
        session.setContent(try SampleContent.image(width: 300, height: 300))
        #expect(session.contentTransform == Self.tabletop.transform && session.layoutPresetID == "tabletop")
        let drag = session.positionDrag(surfaceWidth: 100, surfaceHeight: 100)
        #expect(drag.halfExtentX > 0 && drag.startY == 0.04)
        let empty = EditorSession().positionDrag(surfaceWidth: 100, surfaceHeight: 100)
        #expect(empty.halfExtentX == 0)
    }

    @Test("[S6-AC14] thumbnails are the document with each preset's transform through the one render function")
    func thumbnails() throws {
        let session = try Self.session()
        let presets = [
            LayoutPreset(id: "centered", name: "Centered", transform: .identity), Self.tabletop,
        ]
        let thumbnails = try LayoutThumbnails.render(document: session.document, presets: presets, maxSide: 200)
        #expect(Set(thumbnails.keys) == ["centered", "tabletop"])
        let scale = try #require(LayoutThumbnails.scale(for: session.document, maxSide: 200))
        var variant = session.document
        variant.project.placement = ContentPlacement(transform: Self.tabletop.transform, layoutPresetID: "tabletop")
        let direct = try #require(try Renderer.render(document: variant, scale: scale))
        let thumbnail = try #require(thumbnails["tabletop"])
        #expect(max(thumbnail.width, thumbnail.height) == 200)
        #expect(try PixelBuffer(thumbnail).bytes == PixelBuffer(direct).bytes)
        #expect(try LayoutThumbnails.render(document: EditorDocument(), presets: presets).isEmpty)

        // The cache key ignores the current placement but not the style or content.
        let key = try #require(LayoutThumbnailKey(document: session.document, maxSide: 200))
        var moved = session.document
        moved.project.placement.transform.x = 0.3
        #expect(LayoutThumbnailKey(document: moved, maxSide: 200) == key)
        var restyled = session.document
        restyled.project.border.radius = 4
        #expect(LayoutThumbnailKey(document: restyled, maxSide: 200) != key)
        #expect(LayoutThumbnailKey(document: EditorDocument(), maxSide: 200) == nil)
    }
}
