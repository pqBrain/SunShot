import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Backdrop inspector", .serialized)
struct BackdropInspectorTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 120, height: 80), fileName: "shot.png")
        try #require(model.hasContent)
        return model
    }

    /// Straight RGBA of one pixel (top-left origin).
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }

    @Test("[S3-AC1] the type picker switches through the model, one undo step each, settings remembered")
    func switchKinds() async throws {
        let model = try await loadedModel()
        await model.perform { $0.setBackdropColor(RGBAColor(rgb: 0x123456)) }.value
        for kind in [BackdropKind.none, .gradient, .image, .solid] {
            await model.perform { $0.setBackdropKind(kind) }.value
            #expect(model.project.backdropSettings.kind == kind)
        }
        #expect(model.project.backdrop == .solid(RGBAColor(rgb: 0x123456)))
        #expect(model.undoTitle == "Undo Change Backdrop Type")
        #expect(UIStrings.backdropSection == "Backdrop")
        #expect(BackdropKind.allCases.map(UIStrings.backdropKindName) == ["None", "Solid", "Gradient", "Image"])
        #expect(GradientKind.allCases.map(UIStrings.gradientKindName) == ["Linear", "Radial"])
    }

    @Test("[S3-AC3] None: the preview shows a checkerboard that follows Light/Dark; copy and export stay transparent")
    func transparencyGrid() async throws {
        let model = try await loadedModel()
        await model.perform { $0.setBackdropKind(.none) }.value
        let light = try #require(model.preview)
        #expect(try pixel(light, x: 0, y: 0) == [220, 220, 225, 255])
        #expect(try pixel(light, x: 16, y: 0) == [255, 255, 255, 255])
        await model.setDarkAppearance(true)?.value
        #expect(model.setDarkAppearance(true) == nil, "same appearance: no re-render")
        let dark = try #require(model.preview)
        #expect(try pixel(dark, x: 0, y: 0) == [42, 42, 46, 255])

        try await withPrivatePasteboard { pasteboard in
            await model.copyPNG(to: pasteboard)
            let data = try #require(pasteboard.data(forType: .png))
            let copied = try ImageLoader.load(data)
            #expect(try pixel(copied, x: 0, y: 0)[3] == 0)
        }
        let exported = try ImageLoader.load(try await model.pngData())
        #expect(try pixel(exported, x: 0, y: 0) == [0, 0, 0, 0])
    }

    @Test("[S3-AC5] HEX through the model: valid sets the colour, invalid is refused with no undo step")
    func hexField() async throws {
        let model = try await loadedModel()
        #expect(model.setBackdropColor(hex: "#1a2b3c"))
        #expect(model.project.backdrop == .solid(RGBAColor(rgb: 0x1A2B3C)))
        let title = model.undoTitle
        #expect(!model.setBackdropColor(hex: "#12"))
        #expect(model.undoTitle == title && model.project.backdrop == .solid(RGBAColor(rgb: 0x1A2B3C)))
        #expect(model.setGradientAngle(text: "45°") && !model.setGradientAngle(text: "abc"))
        #expect(model.project.backdropSettings.gradient.angle == 45)
        #expect(UIStrings.hexField == "HEX" && UIStrings.hexFieldAccessibility.contains("HEX"))
    }

    @Test("[S3-AC5] colour-panel streams become one undo step: closed by idle, another edit, or undo")
    func continuousEdits() async throws {
        let model = try await loadedModel()
        let start = model.session.history.undoCount
        let name = EditorSession.backdropColorActionName
        for value in [0x101010, 0x202020, 0x303030] {
            model.performContinuous(name, idle: .seconds(60)) { $0.setBackdropColor(RGBAColor(rgb: UInt32(value))) }
        }
        #expect(model.hasPendingContinuousEdit)
        // Another edit closes the stream first: two steps in total.
        await model.perform { $0.setBackdropKind(.gradient) }.value
        #expect(!model.hasPendingContinuousEdit && model.session.history.undoCount == start + 2)

        // Undo closes an open stream, then undoes it as a whole.
        model.performContinuous(name, idle: .seconds(60)) { $0.setBackdropColor(RGBAColor(rgb: 0x404040)) }
        model.performContinuous(name, idle: .seconds(60)) { $0.setBackdropColor(RGBAColor(rgb: 0x505050)) }
        await model.undo()
        #expect(!model.hasPendingContinuousEdit && model.project.backdropSettings.kind == .gradient)

        // Idle closes it on its own.
        model.performContinuous(name, idle: .milliseconds(20)) { $0.setBackdropColor(RGBAColor(rgb: 0x606060)) }
        model.performContinuous(name, idle: .milliseconds(20)) { $0.setBackdropColor(RGBAColor(rgb: 0x707070)) }
        for _ in 0..<100 where model.hasPendingContinuousEdit { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.hasPendingContinuousEdit && model.undoTitle == "Undo Change Backdrop Colour")
        await model.undo()
        #expect(model.project.backdropSettings.kind == .gradient)

        // A different stream name closes the previous one.
        model.performContinuous(name, idle: .seconds(60)) { $0.setBackdropColor(.white) }
        model.performContinuous(EditorSession.stopColorActionName, idle: .seconds(60)) {
            $0.setGradientStopColor(0, .black)
        }
        model.finishContinuousEdit()
        model.finishContinuousEdit()
        #expect(model.undoTitle == "Undo Change Stop Colour")
    }

    @Test("[S3-AC13] choosing or dropping an image file sets it as the backdrop; bad files alert and change nothing")
    func importImage() async throws {
        let model = try await loadedModel()
        let directory = try TempDirectory()
        defer { directory.cleanUp() }
        let file = directory.file("beach.png")
        try TestImages.png(width: 64, height: 40, red: 0.9).write(to: file)
        let text = directory.file("notes.txt")
        try Data("hello".utf8).write(to: text)

        #expect(await model.importDroppedBackdrop([text]) == false)
        #expect(await model.importDroppedBackdrop([text, file]))
        let reference = try #require(model.project.backdropSettings.mediaReference)
        #expect(reference.fileName == "beach.png" && model.project.backdrop == .image(.file(reference)))
        #expect(model.session.backdropMedia?.data == (try Data(contentsOf: file)))
        #expect(model.undoTitle == "Undo Choose Backdrop Image" && model.alert == nil)

        let before = model.session.document
        await model.importBackdropData(Data("not an image".utf8), fileName: "broken.png")
        #expect(model.alert?.title == EditorModel.backdropImageFailedTitle)
        #expect(model.alert?.message.hasPrefix("broken.png") == true && model.session.document == before)
        #expect(UIStrings.backdropImageFailed == EditorModel.backdropImageFailedTitle)

        model.alert = nil
        await model.importBackdropFile(at: directory.file("missing.png"))
        #expect(model.alert?.title == EditorModel.backdropImageFailedTitle && model.session.document == before)
    }

    @Test("[S3-AC7] [S3-AC15] the library lists swatches, presets and wallpapers with cached same-renderer thumbnails")
    func library() throws {
        let library = BackdropLibrary()
        #expect(library.swatches.count >= 24 && library.gradientPresets.count >= 16 && library.wallpapers.count >= 8)
        let preset = try #require(library.gradientPresets.first)
        let wallpaper = try #require(library.wallpapers.first)
        let thumbnail = try #require(library.thumbnail(for: preset))
        #expect((thumbnail.width, thumbnail.height) == (112, 70))
        #expect(library.thumbnail(for: preset) === thumbnail)
        let wallpaperThumbnail = try #require(library.thumbnail(for: wallpaper))
        #expect(library.thumbnail(for: wallpaper) === wallpaperThumbnail)
        let expected = try Renderer.renderBackdrop(.gradient(preset.spec), size: BackdropLibrary.thumbnailSize)
        #expect(thumbnail.dataProvider?.data == expected.dataProvider?.data)

        let bar = try #require(library.stopBarImage(for: preset.spec))
        #expect((bar.width, bar.height) == (480, 32) && library.stopBarImage(for: preset.spec) === bar)
        let other = try #require(library.gradientPresets.last)
        #expect(library.stopBarImage(for: other.spec) !== bar)

        let empty = BackdropLibrary(
            swatchGroups: { throw TestError.setup }, gradientPresets: { throw TestError.setup },
            wallpapers: { throw TestError.setup })
        #expect(empty.swatches.isEmpty && empty.gradientPresets.isEmpty && empty.wallpapers.isEmpty)
        #expect(BackdropLibrary.shared === BackdropLibrary.shared)
    }

    @Test("[S3-AC20] labels for swatches, presets, wallpapers, stops and the angle")
    func accessibilityLabels() {
        #expect(UIStrings.swatch(name: "Mist", hex: "#EDEDF2", selected: true) == "Mist, #EDEDF2, selected")
        #expect(UIStrings.swatch(name: nil, hex: "#000000", selected: false) == "#000000")
        #expect(UIStrings.gradientPreset("Dawn") == "Gradient preset Dawn")
        #expect(UIStrings.gradientPreset("Dawn", selected: true) == "Gradient preset Dawn, selected")
        #expect(UIStrings.wallpaper("Dunes", selected: true) == "Wallpaper Dunes, selected")
        let stop = GradientStop(position: 0.5, color: RGBAColor(rgb: 0xFF6F91))
        #expect(
            UIStrings.gradientStop(index: 1, count: 3, stop: stop)
                == "Gradient stop 2 of 3, #FF6F91, position 50 percent")
        #expect(UIStrings.angle(139.6) == "140°")
        #expect(UIStrings.backdropImageName(nil) == "Image" && UIStrings.backdropImageName("a.png") == "a.png")
        #expect(!UIStrings.stopBarHint.isEmpty && !UIStrings.noneHint.isEmpty && !UIStrings.backdropDropHint.isEmpty)
    }

    @Test("[S3-AC20] arrow keys move a focused stop by 0.01, ⇧ by 0.1")
    func keyboardNudge() async throws {
        let model = try await loadedModel()
        await model.perform {
            $0.applyGradientPreset(
                GradientSpec(stops: [
                    GradientStop(position: 0, color: .black), GradientStop(position: 0.5, color: .white),
                    GradientStop(position: 1, color: .black),
                ]))
        }.value
        #expect(model.nudgeGradientStop(1, direction: 1, large: false) == 1)
        #expect(abs(model.project.backdropSettings.gradient.stops[1].position - 0.51) < 1e-9)
        #expect(model.nudgeGradientStop(1, direction: -1, large: true) == 1)
        #expect(abs(model.project.backdropSettings.gradient.stops[1].position - 0.41) < 1e-9)
        #expect(model.nudgeGradientStop(7, direction: 1, large: false) == 7, "unknown stop: nothing happens")
        #expect(model.undoTitle == "Undo Move Gradient Stop")
    }

    @Test("[S3-AC20] selection ring and control outlines keep ≥ 3:1 against the inspector in Light and Dark")
    func nonTextContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            // The ring follows the system accent; checked here with the default (blue) accent.
            for color in [SunshotPalette.controlStroke, NSColor.systemBlue] {
                let ratio = Contrast.ratio(color, on: SunshotPalette.inspectorSurface, appearance: appearance)
                #expect(ratio >= 3, "\(name.rawValue): \(color) = \(ratio)")
            }
        }
    }

    @Test("colours round-trip between Sunshot and the system colour panel")
    func colorConversion() throws {
        let color = RGBAColor(rgb: 0x1A2B3C, alpha: 0.5)
        let back = try #require(RGBAColor(nsColor: color.nsColor))
        #expect(back.hexString == color.hexString && abs(back.alpha - 0.5) < 1e-6)
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2)))
        #expect(RGBAColor(nsColor: pattern) == nil)
    }
}
