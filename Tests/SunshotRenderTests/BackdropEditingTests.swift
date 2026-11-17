import CoreGraphics
import Foundation
import SunshotCore
import Testing
import UniformTypeIdentifiers

@testable import SunshotRender

@Suite("Backdrop editing")
struct BackdropEditingTests {
    private func session() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 160, height: 100))
        return session
    }

    @Test("[S3-AC1] switching type is one 'Change Backdrop Type' entry and restores that type's settings")
    func switchType() throws {
        var session = try session()
        let coral = RGBAColor(rgb: 0xFF7F50)
        session.setBackdropColor(coral)
        let count = session.history.undoCount
        session.setBackdropKind(.gradient)
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == "Change Backdrop Type")
        #expect(session.project.backdrop == .gradient(SunshotDefaults.gradient))
        session.setBackdropKind(.gradient)
        #expect(session.history.undoCount == count + 1, "choosing the current type adds nothing")
        session.setBackdropKind(.solid)
        #expect(session.project.backdrop == .solid(coral))
        session.undo()
        #expect(session.project.backdropSettings.kind == .gradient)
    }

    @Test("[S3-AC4] [S3-AC5] swatches and HEX set the exact colour; invalid HEX changes nothing")
    func hexInput() throws {
        var session = try session()
        let swatch = try #require(BackdropCatalog.swatchGroups().last?.swatches.first)
        session.setBackdropColor(swatch.color)
        #expect(session.project.backdrop == .solid(swatch.color))
        #expect(session.history.undoActionName == "Change Backdrop Colour")
        for text in ["#1A2B3C", "1A2B3C", "#1a2b3c80"] {
            let accepted = session.setBackdropColor(hex: text)
            #expect(accepted)
        }
        let expected = RGBAColor(rgb: 0x1A2B3C, alpha: Double(0x80) / 255)
        #expect(session.project.backdropSettings.solidColor == expected)
        let count = session.history.undoCount
        let rejected = ["#12", "ZZZZZZ", ""].filter { !session.setBackdropColor(hex: $0) }
        #expect(rejected.count == 3 && session.history.undoCount == count)
        #expect(session.project.backdropSettings.solidColor == expected)
    }

    @Test("[S3-AC7] a preset replaces kind, angle and stops in one undo entry")
    func preset() throws {
        var session = try session()
        let preset = try #require(BackdropCatalog.gradientPresets().first { $0.spec.kind == .radial })
        let count = session.history.undoCount
        session.applyGradientPreset(preset.spec)
        #expect(session.project.backdrop == .gradient(preset.spec))
        #expect(session.history.undoCount == count + 1 && session.history.undoActionName == "Apply Gradient Preset")
    }

    @Test("[S3-AC8] [S3-AC10] typed angles, gradient type, and each stop edit is its own named undo entry")
    func stopEditing() throws {
        var session = try session()
        session.setBackdropKind(.gradient)
        session.applyGradientPreset(
            GradientSpec(stops: [GradientStop(position: 0, color: .black), GradientStop(position: 1, color: .white)]))
        var names: [String?] = []
        let added = session.addGradientStop(at: 0.5)
        let index = try #require(added)
        names.append(session.history.undoActionName)
        let moved = session.moveGradientStop(index, to: 0.8)
        names.append(session.history.undoActionName)
        session.setGradientStopColor(moved, RGBAColor(rgb: 0xFF0000))
        names.append(session.history.undoActionName)
        let deleted = session.deleteGradientStop(moved)
        names.append(session.history.undoActionName)
        #expect(
            deleted
                && names == ["Add Gradient Stop", "Move Gradient Stop", "Change Stop Colour", "Delete Gradient Stop"])
        let refused = session.deleteGradientStop(0)
        #expect(!refused && session.history.undoActionName == "Delete Gradient Stop")

        let angleAccepted = session.setGradientAngle(text: " 140° ")
        let angleRejected = session.setGradientAngle(text: "wide")
        #expect(angleAccepted && !angleRejected && session.project.backdropSettings.gradient.angle == 140)
        session.setGradientAngle(-90)
        #expect(session.project.backdropSettings.gradient.angle == 270)
        session.setGradientKind(.radial)
        #expect(session.history.undoActionName == "Change Gradient Type")

        // A drag (gesture) is a single entry.
        let count = session.history.undoCount
        session.beginGesture()
        var current = 1
        for step in 1...20 { current = session.moveGradientStop(current, to: 1 - Double(step) / 40) }
        session.endGesture(EditorSession.moveStopActionName)
        #expect(session.history.undoCount == count + 1)
    }

    @Test("[S3-AC13] an imported backdrop keeps the original bytes; unreadable data changes nothing")
    func importImage() throws {
        var session = try session()
        let image = try BackdropFixtures.quadrants(width: 64, height: 32)
        let data = try Fixtures.encode(image, as: .jpeg)
        try session.importBackdropImage(data: data, fileName: "beach.jpg")
        let reference = try #require(session.backdropSettings.mediaReference)
        #expect(session.project.backdrop == .image(.file(reference)))
        #expect(reference.fileName == "beach.jpg" && reference.pixelSize == PixelSize(width: 64, height: 32))
        #expect(session.backdropMedia?.data == data)
        #expect(session.history.undoActionName == "Choose Backdrop Image")

        let before = session.document
        #expect(throws: (any Error).self) { try session.importBackdropImage(data: Data("nope".utf8), fileName: "x") }
        #expect(session.document == before)

        // Choosing a wallpaper drops the unused bytes; undo brings them back.
        let wallpaper = try #require(BackdropCatalog.wallpapers().last)
        session.setWallpaper(wallpaper)
        #expect(session.document.media.isEmpty && session.history.undoActionName == "Choose Wallpaper")
        session.undo()
        #expect(session.backdropMedia?.data == data)
    }

    @Test("[S3-AC15] [S3-AC16] wallpapers are undoable; Reset Backdrop is one entry and a no-op at the default")
    func resetBackdrop() throws {
        var session = try session()
        let count = session.history.undoCount
        session.resetBackdrop()
        #expect(session.history.undoCount == count, "already default")
        let wallpaper = try #require(BackdropCatalog.wallpapers().dropFirst().first)
        session.setWallpaper(wallpaper)
        #expect(session.project.backdrop == .image(.wallpaper(wallpaper)))
        session.applyGradientPreset(SunshotDefaults.gradient)
        session.resetBackdrop()
        #expect(session.project.backdrop == .solid(RGBAColor(rgb: 0xEDEDF2)))
        #expect(session.history.undoActionName == "Reset Backdrop" && session.history.undoCount == count + 3)
        session.undo()
        #expect(session.project.backdrop == .gradient(SunshotDefaults.gradient))
    }

    @Test("[S3-AC17] undo/redo walks over every backdrop mutation and redo-all restores the model")
    func undoWalk() throws {
        var session = try session()
        let start = session.document
        let edits: [(inout EditorSession) throws -> Void] = [
            { $0.setBackdropKind(.none) },
            { $0.setBackdropColor(RGBAColor(rgb: 0x4A4C55)) },
            { _ = $0.setBackdropColor(hex: "#1a2b3c80") },
            { $0.applyGradientPreset(SunshotDefaults.gradient) },
            { $0.setGradientAngle(30) },
            { $0.setGradientKind(.radial) },
            { _ = $0.addGradientStop(at: 0.25) },
            { _ = $0.moveGradientStop(1, to: 0.4) },
            { $0.setGradientStopColor(0, .white) },
            { _ = $0.deleteGradientStop(1) },
            {
                try $0.importBackdropImage(
                    data: Fixtures.encode(Fixtures.solid(width: 8, height: 8), as: .png), fileName: nil)
            },
            { $0.setWallpaper(SunshotDefaults.wallpaper) },
            { $0.resetBackdrop() },
        ]
        for edit in edits { try edit(&session) }
        let end = session.document
        var undone = 0
        while session.history.canUndo, session.document != start {
            session.undo()
            undone += 1
        }
        #expect(session.document == start && undone == edits.count)
        while session.history.canRedo { session.redo() }
        #expect(session.document == end)
    }
}
