import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Backdrop effects editing")
struct EffectsEditingTests {
    private func session(content: CGImage? = nil) throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try content ?? BackdropFixtures.quadrants(width: 160, height: 100))
        return session
    }

    @Test("[S8-AC17] every effect edit is one named undo step; no-op edits record nothing")
    func namedUndoSteps() throws {
        var session = try session()
        let edits: [(String, (inout EditorSession) -> Void)] = [
            (EditorSession.blurActionName, { $0.setBackdropBlur(10) }),
            (EditorSession.noiseActionName, { $0.setBackdropNoise(0.4) }),
            (EditorSession.saturationActionName, { $0.setBackdropSaturation(1.5) }),
            (EditorSession.backdropOpacityActionName, { $0.setBackdropOpacity(0.7) }),
            (EditorSession.patternActionName, { $0.setPatternKind(.dots) }),
            (EditorSession.patternIntensityActionName, { $0.setPatternIntensity(0.8) }),
            (EditorSession.patternThicknessActionName, { $0.setPatternThickness(2) }),
            (EditorSession.patternColorActionName, { $0.setPatternColor(.white) }),
            (EditorSession.vignetteActionName, { $0.setVignetteStyle(.light) }),
            (EditorSession.vignetteSpreadActionName, { $0.setVignetteSpread(0.8) }),
            (EditorSession.vignetteIntensityActionName, { $0.setVignetteIntensity(0.3) }),
            (EditorSession.overlayActionName, { $0.setOverlayKind(.leaves) }),
            (EditorSession.overlayOpacityActionName, { $0.setOverlayOpacity(0.6) }),
            (EditorSession.overlayPositionActionName, { $0.setOverlayPosition(.below) }),
        ]
        for (name, edit) in edits {
            let before = session.backdropEffects
            edit(&session)
            #expect(session.history.undoActionName == name)
            #expect(session.backdropEffects != before, "\(name)")
            let count = session.history.undoCount
            edit(&session)
            #expect(session.history.undoCount == count, "repeating \(name) records nothing")
        }
        let effects = session.backdropEffects
        #expect(effects.adjustments == BackdropAdjustments(blur: 10, noise: 0.4, saturation: 1.5, opacity: 0.7))
        #expect(effects.pattern == BackdropPattern(kind: .dots, intensity: 0.8, thickness: 2, color: .white))
        #expect(effects.vignette == Vignette(style: .light, spread: 0.8, intensity: 0.3))
        #expect(effects.overlay == OverlayTexture(kind: .leaves, opacity: 0.6, position: .below))
        session.undo()
        #expect(session.backdropEffects.overlay.position == .above)
        // Out-of-range values clamp.
        session.setBackdropBlur(500)
        #expect(session.backdropEffects.adjustments.blur == BackdropAdjustments.blurRange.upperBound)
    }

    @Test("[S8-AC17] a slider drag is one undo step; each popover Reset and Reset Backdrop restore defaults")
    func gesturesAndResets() throws {
        var session = try session()
        let count = session.history.undoCount
        session.beginGesture()
        for value in stride(from: 1.0, through: 20, by: 1) { session.setBackdropBlur(value) }
        session.endGesture(EditorSession.blurActionName)
        #expect(session.history.undoCount == count + 1)
        #expect(session.history.undoActionName == EditorSession.blurActionName)

        session.setPatternKind(.grid)
        session.setVignetteStyle(.dark)
        session.setOverlayKind(.window)
        session.resetAdjustments()
        #expect(session.backdropEffects.adjustments == BackdropAdjustments())
        #expect(session.history.undoActionName == EditorSession.resetAdjustmentsActionName)
        session.resetPattern()
        #expect(session.backdropEffects.pattern == BackdropPattern())
        session.resetVignette()
        #expect(session.backdropEffects.vignette == Vignette())
        session.resetOverlay()
        #expect(session.backdropEffects.overlay == OverlayTexture())
        #expect(session.history.undoActionName == EditorSession.resetOverlayActionName)

        session.setPatternKind(.dots)
        session.setBackdropNoise(0.5)
        session.resetBackdrop()
        #expect(session.backdropEffects == BackdropEffects())
        #expect(session.history.undoActionName == EditorSession.resetBackdropActionName)
    }

    @Test("[S8-AC15] five generated suggestions from the content palette; applying one is one undo step")
    func autoSuggestions() throws {
        var session = try session()
        let palette = session.autoPalette
        #expect(palette.count == 6)
        let suggestions = session.autoBackgrounds
        #expect(suggestions.count == AutoBackground.suggestionCount)
        #expect(suggestions == session.autoBackgrounds, "deterministic")
        let thumbnail = try Renderer.renderBackdrop(
            .image(.wallpaper(suggestions[1])), size: PixelSize(width: 112, height: 70))
        #expect((thumbnail.width, thumbnail.height) == (112, 70))
        session.applyAutoBackground(suggestions[2])
        #expect(session.project.backdrop == .image(.wallpaper(suggestions[2])))
        #expect(session.backdropSettings.kind == .image)
        #expect(session.history.undoActionName == EditorSession.autoBackgroundActionName)
        let rendered = try PixelBuffer(#require(try session.render()))
        #expect(rendered.pixel(x: 2, y: 2)[3] == 255, "auto backgrounds are opaque")
        #expect(EditorSession().autoPalette.isEmpty && EditorSession().autoBackgrounds.isEmpty)
    }

    @Test("[S8-AC16] shuffle derives a new arrangement, applies its first suggestion, one undo step")
    func shuffle() throws {
        var session = try session()
        let before = session.autoBackgrounds
        let backdrop = session.project.backdrop
        session.shuffleAutoBackgrounds()
        let after = session.autoBackgrounds
        #expect(session.backdropSettings.autoShuffle == AutoBackground.nextShuffle(after: 0))
        #expect(after != before)
        #expect(session.project.backdrop == .image(.wallpaper(after[0])))
        #expect(session.history.undoActionName == EditorSession.shuffleActionName)
        session.undo()
        #expect(session.project.backdrop == backdrop)
        #expect(session.autoBackgrounds == before)

        var empty = EditorSession()
        empty.shuffleAutoBackgrounds()
        #expect(!empty.history.canUndo)
        #expect(empty.backdropSettings.autoShuffle == 0)
    }

    @Test("[S8-AC15] choosing an auto background drops an unused user image (undo restores it)")
    func autoDropsMedia() throws {
        var session = try session()
        let image = try BackdropFixtures.quadrants(width: 40, height: 30)
        session.setBackdropImage(image, data: try ImageCodec.pngData(image), fileName: "bg.png")
        #expect(session.document.media.count == 1)
        session.applyAutoBackground(try #require(session.autoBackgrounds.first))
        #expect(session.document.media.isEmpty)
        session.undo()
        #expect(session.document.media.count == 1)
    }
}
