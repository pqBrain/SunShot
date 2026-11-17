import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Effects inspector", .serialized)
struct EffectsInspectorTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 120, height: 80), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    @Test("[S8-AC18] labels and VoiceOver strings of the Effects subsection and the Auto block")
    func strings() {
        #expect(UIStrings.effects == "Effects")
        #expect(
            [UIStrings.overlayButton, UIStrings.adjustButton, UIStrings.patternButton, UIStrings.vignetteButton]
                == ["Overlay", "Adjust", "Pattern", "Vignette"])
        #expect(
            PatternKind.allCases.map(UIStrings.patternName)
                == ["None", "Circles", "Waves", "Dots", "Rays", "Grid", "Stripes", "Noise"])
        #expect(
            OverlayKind.allCases.map(UIStrings.overlayName)
                == ["None", "Blinds", "Window", "Leaves", "Lattice", "Ripples", "Dapple"])
        #expect(VignetteStyle.allCases.map(UIStrings.vignetteName) == ["None", "Dark", "Light"])
        #expect(OverlayPosition.allCases.map(UIStrings.overlayPositionName) == ["Above content", "Below content"])
        #expect(UIStrings.effectSliderAccessibility(UIStrings.effectBlur, pixels: 12) == "Blur, 12 pixels")
        #expect(UIStrings.effectSliderAccessibility(UIStrings.effectNoise, percent: 0.4) == "Noise, 40 percent")
        #expect(UIStrings.effectPixels(12.4) == "12 px" && UIStrings.effectPercent(0.355) == "36 %")
        #expect(UIStrings.effectButton("Pattern", value: "Dots", isOn: true) == "Pattern, Dots, on")
        #expect(UIStrings.effectButton("Pattern", value: "None", isOn: false) == "Pattern, None")
        #expect(UIStrings.effectPickerItem("Overlay", "Leaves", selected: true) == "Overlay, Leaves, selected")
        #expect(UIStrings.autoBackground(index: 1, count: 5, selected: false) == "Auto background 2 of 5")
        #expect(UIStrings.paletteAccessibility([.white, .black]) == "Palette: #FFFFFF, #000000")
        #expect(UIStrings.adjustSummary(BackdropAdjustments()) == "None")
        #expect(
            UIStrings.adjustSummary(BackdropAdjustments(blur: 12, noise: 0.4, saturation: 0, opacity: 0.5))
                == "Blur 12 px, Noise 40 %, Saturation 0 %, Opacity 50 %")
    }

    @Test("[S8-AC18] effect edits through the model re-render the preview; Undo names the step")
    func modelEdits() async throws {
        let model = try await loadedModel()
        let before = try #require(model.preview)
        await model.perform { $0.setPatternKind(.stripes) }.value
        #expect(model.undoTitle == "Undo Change Pattern")
        let after = try #require(model.preview)
        #expect(try ImageCodec.pngData(after) != ImageCodec.pngData(before))
        model.beginGesture()
        for value in [0.1, 0.2, 0.3] { model.perform { $0.setBackdropNoise(value) } }
        model.endGesture(EditorSession.noiseActionName)
        #expect(model.undoTitle == "Undo Change Backdrop Noise")
        await model.undo()
        #expect(model.project.backdropSettings.effects.adjustments.noise == 0)
        #expect(model.project.backdropSettings.effects.pattern.kind == .stripes)
    }

    @Test(
        "[S8-AC15] [S8-AC18] the auto store gives the palette and five thumbnails, cached until content or shuffle change"
    )
    func autoStore() async throws {
        let store = AutoBackgroundStore()
        #expect(store.state(for: EditorSession()).suggestions.isEmpty)
        let model = try await loadedModel()
        let state = store.state(for: model.session)
        #expect(state.palette.count == 6)
        #expect(state.suggestions.count == 5)
        #expect(state.suggestions.allSatisfy { $0.thumbnail?.width == BackdropLibrary.thumbnailSize.width })
        #expect(store.state(for: model.session).suggestions.map(\.id) == state.suggestions.map(\.id))
        await model.perform { $0.shuffleAutoBackgrounds() }.value
        let shuffled = store.state(for: model.session)
        #expect(shuffled.palette == state.palette)
        #expect(shuffled.suggestions.map(\.id) != state.suggestions.map(\.id))
        #expect(model.project.backdrop == .image(.wallpaper(shuffled.suggestions[0].wallpaper)))
        #expect(model.undoTitle == "Undo Shuffle Auto Backgrounds")
    }

    @Test("[S8-AC7] [S8-AC10] pattern and overlay picker thumbnails are drawn by the renderer and differ")
    func thumbnails() throws {
        let thumbnails = EffectThumbnails()
        let patterns = PatternKind.allCases.dropFirst().compactMap(thumbnails.pattern)
        let overlays = OverlayKind.allCases.dropFirst().compactMap(thumbnails.overlay)
        #expect(patterns.count == 7 && overlays.count == 6)
        let encoded = try (patterns + overlays).map { try ImageCodec.pngData($0) }
        #expect(Set(encoded).count == 13, "every thumbnail is different")
        #expect(thumbnails.pattern(.dots) === thumbnails.pattern(.dots), "cached")
    }
}
