import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Auto backdrop on the first import")
struct AutoBackdropImportTests {
    private func image(red: CGFloat) throws -> CGImage { try Fixtures.solid(width: 40, height: 30, red: red) }

    private func expectedWallpaper(for image: CGImage, shuffle: UInt64 = 0) throws -> Wallpaper {
        let palette = ContentPalette.extract(from: image)
        return try #require(AutoBackground.suggestions(palette: palette, shuffle: shuffle).first)
    }

    @Test("[S7-AC25] the first image styles an untouched backdrop in the Import Image undo step")
    func firstImportStylesBackdrop() throws {
        var session = EditorSession()
        #expect(session.project.hasUntouchedBackdrop)
        let first = try image(red: 0.8)
        session.setContent(first, autoBackdrop: true)
        #expect(session.project.backdrop == .image(.wallpaper(try expectedWallpaper(for: first))))
        #expect(!session.project.hasUntouchedBackdrop)
        #expect(session.history.undoActionName == EditorSession.importActionName)
        session.undo()
        #expect(!session.hasContent && session.project.hasUntouchedBackdrop && !session.history.canUndo)
        session.redo()
        #expect(session.project.backdrop == .image(.wallpaper(try expectedWallpaper(for: first))))
    }

    @Test("[S7-AC25] replacing, a changed backdrop or the flag off leave the backdrop alone")
    func leavesChosenBackdropsAlone() throws {
        // Off: the default backdrop stays.
        var off = EditorSession()
        off.setContent(try image(red: 0.8))
        #expect(off.project.hasUntouchedBackdrop)
        // Replace: only the first image of a document restyles.
        off.setContent(try image(red: 0.1), autoBackdrop: true)
        #expect(off.project.hasUntouchedBackdrop)
        // A colour the user picked is kept.
        var picked = EditorSession()
        picked.setBackdropColor(RGBAColor(red: 1, green: 0, blue: 0))
        picked.setContent(try image(red: 0.8), autoBackdrop: true)
        #expect(picked.project.backdrop == .solid(RGBAColor(red: 1, green: 0, blue: 0)))
        // So are backdrop effects on the default colour.
        var blurred = EditorSession()
        blurred.setBackdropBlur(10)
        #expect(!blurred.project.hasUntouchedBackdrop)
        blurred.setContent(try image(red: 0.8), autoBackdrop: true)
        #expect(blurred.project.backdrop == Project().backdrop)
    }

    @Test("[S7-AC25] after Clear the auto backdrop stays and is not re-rolled by the next image")
    func clearKeepsAutoBackdrop() throws {
        var session = EditorSession()
        let first = try image(red: 0.8)
        session.setContent(first, autoBackdrop: true)
        let styled = session.project.backdrop
        session.clearContent()
        session.setContent(try image(red: 0.1), autoBackdrop: true)
        #expect(session.project.backdrop == styled)
    }
}
