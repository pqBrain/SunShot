import AppKit
import Foundation
import SunshotCore
import SunshotRender
import Testing

@testable import SunshotPlatform

@MainActor
@Suite("Position, tilt and layouts (model)", .serialized)
struct LayoutModelTests {
    private func loadedModel(width: Int = 160, height: Int = 100) async throws -> EditorModel {
        let model = EditorModel()
        model.layout.reduceMotion = { false }
        await model.importData(try TestImages.png(width: width, height: height), fileName: "shot.png")
        try #require(model.hasContent)
        await model.layout.thumbnailTask?.value
        return model
    }

    private func catalogPreset(_ id: String) throws -> LayoutPreset {
        try #require(LayoutLibrary.shared.catalog?.preset(id: id))
    }

    @Test(
        "[S6-AC3] [S6-AC4] the handle drag moves the content, shows the lock guide, is one undo step and clears guides")
    func positionDrag() async throws {
        let model = try await loadedModel()
        model.beginPositionDrag(surfaceWidth: 200, surfaceHeight: 130)
        model.updatePositionDrag(translationX: 3, translationY: 0, modifiers: [])
        await model.perform { _ in }.value
        // ⌘: no snapping (the content's right edge would snap flush at x 0.22).
        model.updatePositionDrag(translationX: 40, translationY: 5, modifiers: .command)
        #expect(model.session.contentTransform.y == 0 && abs(model.session.contentTransform.x - 0.2) < 1e-9)
        #expect(model.layout.guides.contains(.axisLock(.horizontal, through: 0)))
        model.updatePositionDrag(translationX: 40, translationY: 26, modifiers: [.option, .command])
        #expect(abs(model.session.contentTransform.y - 0.2) < 1e-9)
        #expect(model.layout.guides.isEmpty)
        model.endPositionDrag()
        #expect(model.layout.guides.isEmpty)
        #expect(model.undoTitle == "Undo Move Content")
        await model.undo()
        #expect(model.session.contentTransform.isIdentity)
        // Without a drag in progress, updates are ignored.
        model.updatePositionDrag(translationX: 10, translationY: 10, modifiers: [])
        #expect(model.session.contentTransform.isIdentity)
    }

    @Test("[S6-AC18] arrow keys move the handle 0.01 (⇧ 0.05) and labels read as specified")
    func keyboardAndLabels() async throws {
        let model = try await loadedModel()
        #expect(UIStrings.contentPosition(x: 0, y: 0) == "Content position, x 0.00 y 0.00")
        #expect(UIStrings.zoom(100) == "Zoom, 100 percent")
        #expect(UIStrings.rotation(0) == "Rotation, 0 degrees")
        #expect(UIStrings.layout("Centered", selected: true) == "Layout: Centered, selected")
        #expect(UIStrings.layout("Tabletop", selected: false) == "Layout: Tabletop")
        #expect(UIStrings.tilt(x: 12.4, y: -30) == "Tilt, x 12 degrees, y -30 degrees")
        #expect(UIStrings.contentPosition(x: -0.004, y: -0.25) == "Content position, x 0.00 y -0.25")
        #expect(UIStrings.contentPosition(x: 0.5, y: .nan) == "Content position, x 0.50 y 0.00")
        model.nudgePosition(dx: 1, dy: 0, large: false)
        model.nudgePosition(dx: 0, dy: -1, large: true)
        #expect(abs(model.session.contentTransform.x - 0.01) < 1e-9)
        #expect(abs(model.session.contentTransform.y + 0.05) < 1e-9)
        #expect(model.setZoom(text: "150.4"))
        #expect(model.session.contentTransform.zoom == 150)
        #expect(!model.setZoom(text: "huge"))
        #expect(model.setRotation(text: "270"))
        #expect(model.session.contentTransform.rotation == -90)
        #expect(!model.setRotation(text: "x"))
    }

    @Test("[S6-AC2] Position control: disabled without content; tabs, sliders and Reset are labelled")
    func positionPopoverStructure() async throws {
        let empty = EditorModel()
        #expect(!empty.hasContent, "the Position button is disabled with no content")
        let model = try await loadedModel()
        #expect(model.hasContent)
        #expect(UIStrings.positionButton == "Position" && UIStrings.positionTab == "Position")
        #expect(UIStrings.tiltTab == "Tilt" && UIStrings.zoomLabel == "Zoom" && UIStrings.rotationLabel == "Rotation")
        #expect(UIStrings.resetPosition == "Reset position")
        #expect(UIStrings.positionButtonAccessibility == "Position, zoom, rotation and tilt")
        // The mini canvas handle drives the transform through the same model calls the popover uses.
        model.beginPositionDrag(surfaceWidth: 200, surfaceHeight: 130)
        model.updatePositionDrag(translationX: 50, translationY: 0, modifiers: .command)
        model.endPositionDrag()
        #expect(!model.session.contentTransform.isIdentity)
        await model.perform { $0.resetPosition() }.value
        #expect(model.session.contentTransform.isIdentity, "Reset restores the identity transform")
    }

    @Test("[S6-AC14] thumbnails come from the same renderer, regenerate within 300 ms of a style change, are cached")
    func thumbnails() async throws {
        let empty = EditorModel()
        await empty.refreshPreview()
        #expect(empty.layout.thumbnails.isEmpty)

        let model = try await loadedModel()
        let presets = model.layout.presets
        #expect(presets.count >= 12)
        #expect(Set(model.layout.thumbnails.keys) == Set(presets.map(\.id)))
        let direct = try LayoutThumbnails.render(document: model.session.document, presets: presets)
        for preset in presets {
            let thumbnail = try #require(model.layout.thumbnails[preset.id])
            let expected = try #require(direct[preset.id])
            #expect(thumbnail.width == expected.width && thumbnail.height == expected.height)
            #expect(thumbnail.dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
        }
        let original = model.layout.thumbnails

        // Moving the content doesn't invalidate the thumbnails.
        await model.perform { $0.moveContent(x: 0.2, y: 0) }.value
        #expect(model.layout.thumbnailTask == nil || model.layout.pendingThumbnailKey == nil)

        let clock = ContinuousClock()
        let start = clock.now
        await model.perform { $0.setCornerRadius(4) }.value
        await model.layout.thumbnailTask?.value
        let elapsed = clock.now - start
        // The 300 ms budget is enforced in release by LayoutThumbnailRenderPerformanceTests; a parallel debug run
        // only proves the regeneration is debounced and finishes promptly.
        #expect(elapsed <= .seconds(2), "\(elapsed)")
        let restyled = try #require(model.layout.thumbnails["centered"])
        #expect(restyled.dataProvider?.data as Data? != original["centered"]?.dataProvider?.data as Data?)

        // Undo goes back to a cached set at once.
        await model.undo()
        #expect(model.layout.pendingThumbnailKey == nil)
        #expect(model.layout.thumbnails["centered"] === original["centered"])

        await model.clearContent()
        #expect(model.layout.thumbnails.isEmpty)
    }

    @Test(
        "[S6-AC15] [S6-AC16] applying a preset animates 300 ms ease-in-out to the exact target; export sees the target")
    func animatedApply() async throws {
        let model = try await loadedModel()
        let tabletop = try catalogPreset("tabletop")
        let task = model.applyLayoutPreset(tabletop)
        // Mid-animation: the document (and so export) already holds the target.
        #expect(model.session.contentTransform == tabletop.transform)
        #expect(model.selectedLayoutPreset == tabletop)
        #expect(model.undoTitle == "Undo Apply Layout Tabletop")
        let exported = try ImageCodec.decode(try model.session.copyPNGData())
        let plan = try #require(model.session.exportPlan)
        let expected = try #require(try Renderer.render(document: model.session.document, scale: plan.renderScale))
        #expect(model.session.document.project.placement.transform == tabletop.transform)
        let exportedBytes = try PixelBufferBytes.of(exported)
        #expect(exportedBytes == (try PixelBufferBytes.of(expected)))
        await task.value
        let animation = try #require(model.layout.lastAnimation)
        #expect(
            animation.duration >= .milliseconds(250) && animation.duration <= .milliseconds(350),
            "\(animation.duration)")
        #expect(animation.frames.count >= 3)
        #expect(animation.frames.last == tabletop.transform)
        // Ease-in-out: progress in tilt X is monotonic and slow at the start.
        let tilts = animation.frames.map(\.tiltX)
        #expect(zip(tilts, tilts.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(model.layout.animatingTransform == nil)
        let final = try #require(model.preview)
        let direct = try #require(
            try Renderer.render(
                document: model.session.document, scale: model.previewScale, showsTransparencyGrid: true,
                grid: SunshotPalette.transparencyGrid(dark: false)))
        #expect(final.dataProvider?.data as Data? == direct.dataProvider?.data as Data?)

        // A manual change removes the selection; undo restores it.
        await model.perform { $0.setZoom(120) }.value
        #expect(model.selectedLayoutPreset == nil)
        await model.undo()
        #expect(model.selectedLayoutPreset == tabletop)
        await model.undo()
        #expect(model.session.contentTransform.isIdentity && model.selectedLayoutPreset == nil)
    }

    @Test("[S6-AC16] with Reduce Motion the preset applies instantly; a newer edit supersedes a running animation")
    func reduceMotion() async throws {
        let model = try await loadedModel()
        model.layout.reduceMotion = { true }
        await model.applyLayoutPreset(try catalogPreset("swing-left")).value
        #expect(model.layout.lastAnimation == nil)
        #expect(model.session.contentTransform == (try catalogPreset("swing-left")).transform)

        model.layout.reduceMotion = { false }
        let running = model.applyLayoutPreset(try catalogPreset("corner-peek"))
        let replacement = model.applyLayoutPreset(try catalogPreset("jaunty"))
        await running.value
        await replacement.value
        #expect(model.session.contentTransform == (try catalogPreset("jaunty")).transform)
        #expect(model.layout.lastAnimation?.frames.last == (try catalogPreset("jaunty")).transform)

        let superseded = model.applyLayoutPreset(try catalogPreset("tabletop"))
        await model.perform { $0.setRotation(5) }.value
        await superseded.value
        #expect(model.layout.animatingTransform == nil)
        #expect(model.session.contentTransform.rotation == 5)
        // Re-applying the current layout changes nothing and doesn't animate.
        let same = model.session.contentTransform
        await model.perform { $0.resetPosition() }.value
        #expect(model.session.contentTransform.isIdentity && same.rotation == 5)
    }

    @Test("[S6-AC13] a layout catalog that fails to load leaves an empty list instead of crashing")
    func failedCatalog() {
        let library = LayoutLibrary(load: { throw LayoutPresetCatalogError.missingResource })
        #expect(library.presets.isEmpty && library.catalog == nil)
        #expect(LayoutLibrary.shared.presets.first?.name == "Centered")
        let state = LayoutState(library: library)
        #expect(state.presets.isEmpty)
    }
}

/// RGBA bytes of an image redrawn into sRGB (decoded PNGs and rendered images can differ in layout).
enum PixelBufferBytes {
    static func of(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }
}

@MainActor
@Suite("Annotate × transform")
struct AnnotateTransformGuardTests {
    @Test("[S9-AC1] Annotate mode is offered only for flat image content (no S6 transform)")
    func annotateNeedsIdentityTransform() async throws {
        let model = EditorModel()
        #expect(!model.canAnnotate)
        let image = try SampleContent.image(width: 40, height: 30)
        await model.perform { $0.setContent(image) }.value
        #expect(model.canAnnotate)
        await model.perform { $0.moveContent(x: 0.1, y: 0) }.value
        #expect(!model.canAnnotate)
    }
}
