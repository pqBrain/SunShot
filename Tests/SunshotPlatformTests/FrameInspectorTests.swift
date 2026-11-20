import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Frame and Colors & Fonts inspector", .serialized)
struct FrameInspectorTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 120, height: 80), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    @Test("[S5-AC1] ten named frame options with live thumbnails; selecting one is \"Change Frame\"")
    func framePicker() async throws {
        let names = FrameKind.allCases.map(UIStrings.frameName)
        #expect(
            names == [
                "None", "Mac window", "Browser window", "Card", "Stack", "Stack 2", "Stack 3", "Stack 4",
                "Thick border", "Windows window",
            ])
        let model = try await loadedModel()
        for kind in FrameKind.allCases {
            let thumbnail = try #require(model.frameThumbnail(kind))
            #expect(thumbnail.width == EditorModel.frameThumbnailSize.width)
        }
        #expect(model.frameThumbnail(.card) === model.frameThumbnail(.card))
        await model.perform { $0.setFrameKind(.macWindow) }.value
        #expect(model.undoTitle == "Undo Change Frame")
        #expect(model.project.frame.kind == .macWindow)
    }

    @Test("[S5-AC9] canvas title edit: live preview, Return commits one entry, Esc restores")
    func inlineTitle() async throws {
        let model = try await loadedModel()
        await model.perform { $0.setFrameKind(.macWindow) }.value
        let bar = try #require(model.titleBarUnitRect)
        // 120×80 content + 28 px bar + 64 px padding: the bar spans the content width at the top of the box.
        #expect(abs(bar.minX - 64.0 / 248) < 1e-9 && abs(bar.minY - 64.0 / 236) < 1e-9)
        #expect(abs(bar.height - 28.0 / 236) < 1e-9)
        model.beginTitleEdit()
        model.updateTitle("Release")
        model.updateTitle("Release notes")
        #expect(model.project.frame.title == "Release notes")
        model.commitTitleEdit()
        #expect(model.undoTitle == "Undo Edit Frame Title")
        #expect(model.previewAccessibilityValue == "Release notes")

        model.beginTitleEdit()
        model.updateTitle("Oops")
        model.cancelTitleEdit(restoring: "Release notes")
        #expect(model.project.frame.title == "Release notes")
        #expect(model.undoTitle == "Undo Edit Frame Title")
        await model.perform { $0.setFrameKind(.card) }.value
        #expect(model.titleBarUnitRect == nil && model.previewAccessibilityValue == "")
    }

    @Test("[S5-AC12] typed HEX per token: invalid input changes nothing")
    func tokenHex() async throws {
        let model = try await loadedModel()
        let title = model.undoTitle
        #expect(!model.setTokenColor(.background, hex: "nope"))
        #expect(model.undoTitle == title)
        #expect(model.setTokenColor(.background, hex: "#101014"))
        #expect(model.project.tokens.colors.background.hexString == "#101014")
        #expect(model.undoTitle == "Undo Change Background Color")
    }

    @Test("[S5-AC15] font pickers: recommended fonts first, system fallback, \"Font unavailable\"")
    func fontLibrary() {
        let text = FontLibrary.recommended(.text)
        let code = FontLibrary.recommended(.code)
        #expect(text.count >= 3 && text.first?.postScriptName == "")
        #expect(code.count >= 2 && code.contains { $0.postScriptName == "Menlo-Regular" })
        let installedCode = FontLibrary.installed(.code)
        #expect(!installedCode.contains { option in code.contains(option) })
        #expect(!FontLibrary.installed(.text).isEmpty)
        #expect(FontLibrary.displayName("", role: .text) == "System")
        #expect(FontLibrary.displayName("Georgia", role: .text) == "Georgia")
        #expect(FontLibrary.displayName("NoSuchFont-Regular", role: .text) == "Font unavailable")
        #expect(!FontLibrary.isAvailable("NoSuchFont-Regular"))
    }

    @Test("[S5-AC15] every font file in the repository has a licence in LICENSES/ (none are bundled)")
    func fontLicences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let fonts = enumerator.compactMap { $0 as? URL }.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension) }
        let licences =
            (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("LICENSES").path))
            ?? []
        for font in fonts {
            let family =
                font.deletingPathExtension().lastPathComponent.split(separator: "-").first.map(String.init) ?? ""
            #expect(licences.contains { $0.hasPrefix(family) }, "\(font.lastPathComponent) has no licence file")
        }
    }

    @Test("[S5-AC20] VoiceOver labels for frame tiles, UI scale, colour wells and fonts")
    func accessibilityLabels() {
        #expect(UIStrings.frameOption(.macWindow, selected: true) == "Frame: Mac window, selected")
        #expect(UIStrings.frameOption(.card, selected: false) == "Frame: Card")
        #expect(UIStrings.uiScale(100) == "UI scale, 100 percent")
        #expect(UIStrings.tokenWell(.foreground) == "Foreground color")
        #expect(ColorToken.allCases.map(UIStrings.tokenName) == ["Foreground", "Background", "Secondary", "Primary"])
        #expect(ChromeAppearance.allCases.map(UIStrings.appearanceName) == ["Light", "Dark", "Auto"])
        #expect(UIStrings.fontPicker(.text) == "Text font" && UIStrings.fontPicker(.code) == "Code font")
        #expect(UIStrings.frameSection == "Frame" && UIStrings.colorsSection == "Colors & Fonts")
    }
}
