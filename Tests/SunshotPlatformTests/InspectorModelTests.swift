import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Inspector (border and shadow)", .serialized)
struct InspectorModelTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 120, height: 80), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    @Test("[S2-AC1] Border and Shadow sections with Reset; disabled with a placeholder when empty")
    func sections() async throws {
        let empty = EditorModel()
        #expect(empty.showsInspector)
        #expect(!empty.isInspectorEnabled)
        #expect(UIStrings.inspectorEmpty == "Add an image to style it.")
        #expect(UIStrings.borderSection == "Border" && UIStrings.shadowSection == "Shadow")
        #expect(UIStrings.resetSection(UIStrings.borderSection) == "Reset Border")
        #expect(UIStrings.toggleInspector.contains("⌥⌘E"))
        let model = try await loadedModel()
        #expect(model.isInspectorEnabled)
        model.showsInspector.toggle()
        #expect(!model.showsInspector)
    }

    @Test("[S2-AC6] slider drag = one undo step and the preview follows; typed 80 matches")
    func radiusControl() async throws {
        let model = try await loadedModel()
        let undoTitle = model.undoTitle
        model.beginGesture()
        for value in stride(from: 30.0, through: 80, by: 10) { model.perform { $0.setCornerRadius(value) } }
        model.endGesture(EditorSession.cornerRadiusActionName)
        await model.perform { _ in }.value
        #expect(model.project.border.radius == 80)
        #expect(model.undoTitle == "Undo Change Corner Radius")
        let preview = try #require(model.preview)
        let expected = try #require(try model.session.render(scale: 1))
        #expect(preview.width == expected.width)

        await model.undo()
        #expect(model.project.border.radius == 24 && model.undoTitle == undoTitle)
        #expect(model.setCornerRadius(text: "80"))
        #expect(model.project.border.radius == 80)
        #expect(!model.setCornerRadius(text: "eighty"))
        #expect(model.project.border.radius == 80)
    }

    @Test("[S2-AC11] arrow keys move the light by 0.02, ⇧ by 0.1, clamped; VoiceOver label follows")
    func keyboardLight() async throws {
        let model = try await loadedModel()
        model.perform { $0.setLightPosition(.zero) }
        model.nudgeLight(dx: 1, dy: 0, large: false)
        #expect(abs(model.project.shadow.lightPosition.x - 0.02) < 1e-9)
        model.nudgeLight(dx: 0, dy: -1, large: true)
        #expect(abs(model.project.shadow.lightPosition.y + 0.1) < 1e-9)
        #expect(UIStrings.lightDirection(model.project.shadow.lightPosition) == "Light direction, x 0.02, y -0.1")
        for _ in 0..<30 { model.nudgeLight(dx: 1, dy: 0, large: true) }
        let position = model.project.shadow.lightPosition
        #expect(hypot(position.x, position.y) <= 1 + 1e-9)
        #expect(UIStrings.lightDirection(SunshotDefaults.shadowOffset) == "Light direction, x 0, y 0.35")
        #expect(UIStrings.lightDirection(Shadow().lightPosition) == "Light direction, x 0, y -0.35")
    }

    @Test("[S2-AC18] inspector text ≥ 4.5:1 and control outlines ≥ 3:1 in Light and Dark")
    func contrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            for text in [SunshotPalette.primaryText, SunshotPalette.secondaryText] {
                let ratio = Contrast.ratio(text, on: SunshotPalette.inspectorSurface, appearance: appearance)
                #expect(ratio >= 4.5, "\(name.rawValue) text \(ratio)")
            }
            for background in [SunshotPalette.inspectorSurface, SunshotPalette.workspaceBackground] {
                let ratio = Contrast.ratio(SunshotPalette.controlStroke, on: background, appearance: appearance)
                #expect(ratio >= 3, "\(name.rawValue) control \(ratio)")
            }
        }
    }

    @Test("[S2-AC18] a styled export is identical in Light and Dark appearance")
    func exportIgnoresAppearance() async throws {
        let model = try await loadedModel()
        model.perform {
            $0.setCornerStyle(.round)
            $0.setShadowStyle(.hug)
        }
        var outputs: [Data] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            var png = Data()
            try appearance.performAsCurrentDrawingAppearanceThrowing { png = try model.session.exportPNG() }
            outputs.append(png)
        }
        #expect(outputs[0] == outputs[1])
    }

    @Test("[S2-AC19] every border and shadow control has a spoken label")
    func labels() {
        #expect(UIStrings.cornerStyle(.smooth) == "Corner style: smooth")
        #expect(UIStrings.cornerRadius(24) == "Corner radius, 24 pixels")
        #expect(UIStrings.shadowStyle(.spread) == "Shadow style: spread")
        #expect(UIStrings.shadowIntensity(.medium) == "Shadow intensity: medium")
        for style in CornerStyle.allCases { #expect(!UIStrings.cornerStyleName(style).isEmpty) }
        for style in ShadowStyle.allCases { #expect(!UIStrings.shadowStyleName(style).isEmpty) }
        for intensity in ShadowIntensity.allCases { #expect(!UIStrings.intensityName(intensity).isEmpty) }
    }

    @Test("[S2-AC12] Reset buttons go through the model as single undo steps")
    func resetThroughModel() async throws {
        let model = try await loadedModel()
        model.perform { $0.setShadowIntensity(.high) }
        model.perform { $0.resetShadow() }
        #expect(model.project.shadow == Shadow())
        #expect(model.undoTitle == "Undo Reset Shadow")
    }
}
