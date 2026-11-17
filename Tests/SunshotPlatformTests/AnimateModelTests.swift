import AppKit
import CoreGraphics
import Foundation
import SunshotCore
import SunshotRender
import Testing
import UniformTypeIdentifiers

@testable import SunshotPlatform

@MainActor
@Suite("Animate mode (model)", .serialized)
struct AnimateModelTests {
    private func loadedModel() async throws -> EditorModel {
        let model = EditorModel()
        await model.importData(try TestImages.png(width: 160, height: 100), fileName: "shot.png")
        try #require(model.hasContent)
        model.animate.frameInterval = .milliseconds(1)
        return model
    }

    /// A short movie made by the app's own exporter (no audio).
    private func movie(in folder: TempDirectory) async throws -> URL {
        var project = Project()
        project.timeline = AnimationTimeline(clips: [AnimationClip(target: ContentTransform(zoom: 150))])
        project.timeline.video.resolution = .p720
        let document = EditorDocument(
            project: project, content: ContentImage(try TestImages.solid(width: 80, height: 60)))
        let url = folder.file("source.mp4")
        try await VideoExporter.export(document, to: url)
        return url
    }

    @Test("[S13-AC17] playback advances in real time, renders through the renderer and stops at the end")
    func playback() async throws {
        let model = try await loadedModel()
        model.setAnimateMode(true)
        #expect(model.animate.isActive)
        await model.addClip().value
        let id = try #require(model.animate.selectedClipID)
        model.setClipDuration(milliseconds: 200)
        model.setClipHold(milliseconds: 0)
        #expect(model.timeline.clips.first?.id == id && model.animationDuration == 1)
        let clock = ContinuousClock()
        let start = clock.now
        model.play()
        #expect(model.animate.isPlaying)
        model.play()
        await model.animate.playbackTask?.value
        #expect(start.duration(to: clock.now) >= .milliseconds(900), "real time, not as fast as possible")
        #expect(!model.animate.isPlaying && model.animate.playhead == 1)
        let frame = try #require(model.displayedPreview)
        let expected = try #require(
            try AnimationRenderer.render(
                model.session.document, at: 1, scale: model.previewScale, showsTransparencyGrid: true,
                grid: SunshotPalette.transparencyGrid(dark: false)))
        #expect(frame.width == expected.width && frame.height == expected.height)
        #expect(frame.dataProvider?.data == expected.dataProvider?.data)

        model.play()
        #expect(model.animate.playhead == 0, "play at the end starts over")
        try await Task.sleep(for: .milliseconds(150))
        model.togglePlayback()
        let paused = model.animate.playhead
        #expect(!model.animate.isPlaying && paused > 0 && paused < 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.animate.playhead == paused)
    }

    @Test("[S13-AC17] seeking renders the frame without touching the document or history")
    func seeking() async throws {
        let model = try await loadedModel()
        model.setAnimateMode(true)
        await model.addClip().value
        let document = model.session.document
        let undo = model.session.history.undoNames
        await model.seek(to: 1.0).value
        let middle = try #require(model.animate.frame)
        await model.seekToEnd().value
        #expect(model.animate.playhead == model.animationDuration)
        let end = try #require(model.animate.frame)
        #expect(middle.dataProvider?.data != end.dataProvider?.data)
        await model.seekToStart().value
        #expect(model.animate.playhead == 0)
        await model.seek(to: 99).value
        #expect(model.animate.playhead == model.animationDuration)
        await model.seek(to: .nan).value
        #expect(model.animate.playhead == 0)
        #expect(model.session.document == document && model.session.history.undoNames == undo)
        #expect(model.timecodeText == "00:00.00 / 00:02.00")
        #expect(model.animationFrameRequest == model.animationFrameRequest)
        model.setAnimateMode(false)
        #expect(model.animate.frame == nil && model.displayedPreview == model.preview)
        await model.renderAnimationFrame()
        #expect(model.animate.frame == nil, "no frames outside Animate mode")
    }

    @Test("[S13-AC5] clip editing from the model: selection, reorder, easing, target, mute — all undoable")
    func clipEditing() async throws {
        let model = try await loadedModel()
        model.setAnimateMode(true)
        await model.addClip().value
        let first = try #require(model.animate.selectedClipID)
        model.selectClip(first)
        #expect(model.animate.playhead == 1.5)
        await model.addClip().value
        let second = try #require(model.animate.selectedClipID)
        #expect(model.timeline.clips.map(\.id) == [first, second])
        model.moveSelectedClip(by: -1)
        #expect(model.timeline.clips.map(\.id) == [second, first])
        model.setEasing(.linear)
        #expect(model.selectedClip?.easing == .linear)
        model.beginGesture()
        model.setClipTarget { $0.rotation = 30 }
        model.setClipTarget { $0.rotation = 45 }
        model.endGesture(EditorSession.clipTargetActionName)
        #expect(model.selectedClip?.target.rotation == 45)
        model.perform { $0.setRotation(10) }
        model.setClipTargetToCurrentLayout()
        #expect(model.selectedClip?.target == ContentTransform(rotation: 10))
        model.toggleMute()
        #expect(model.isMuted)
        model.deleteSelectedClip()
        #expect(model.timeline.clips.map(\.id) == [first] && model.animate.selectedClipID == nil)
        model.deleteSelectedClip()
        model.setEasing(.out)
        model.moveSelectedClip(by: 1)
        model.setClipDuration(milliseconds: 5)
        model.setClipHold(milliseconds: 5)
        model.setClipTarget { $0.zoom = 300 }
        #expect(
            model.session.history.undoNames.suffix(9) == [
                "Add Animation", "Add Animation", "Move Animation", "Change Easing", "Change Animation Target",
                "Rotate Content", "Change Animation Target", "Mute Audio", "Delete Animation",
            ])
        await model.undo()
        #expect(model.timeline.clips.count == 2)
    }

    @Test("[S13-AC7] Animate needs content; video drops import; a bad movie shows an alert")
    func modeAndImport() async throws {
        let folder = try TempDirectory()
        defer { folder.cleanUp() }
        let empty = EditorModel()
        empty.setAnimateMode(true)
        #expect(!empty.animate.isActive && !empty.canAnimate)

        let model = try await loadedModel()
        model.annotate.isActive = true
        model.toggleAnimateMode()
        #expect(model.animate.isActive && !model.annotate.isActive)
        let bad = folder.file("broken.mov")
        try Data("nope".utf8).write(to: bad)
        #expect(model.canAcceptDrop([bad]))
        #expect(await model.importDroppedFiles([bad]))
        #expect(model.alert?.title == EditorModel.openFailedTitle && !model.hasVideoContent)
        model.alert = nil

        let url = try await movie(in: folder)
        #expect(await model.importDroppedFiles([url]))
        #expect(model.hasVideoContent && model.session.history.undoNames.last == "Import Video")
        await model.seek(to: 0.5).value
        #expect(model.animate.frame != nil && model.animate.videoSource != nil)
        #expect(model.animationDuration == 2, "the 2 s movie sets the length")
    }

    @Test("[S13-AC14] export from the model: progress, notice, cancel leaves nothing; options are undoable")
    func exportFlow() async throws {
        let folder = try TempDirectory()
        defer { folder.cleanUp() }
        let model = try await loadedModel()
        await model.addClip().value
        model.setVideoOptions { $0.resolution = .p720 }
        #expect(
            model.videoOptions.resolution == .p720 && model.session.history.undoNames.last == "Change Video Options")
        #expect(model.videoResolutionText.hasSuffix("× 720") && model.videoDurationText == "2s")
        #expect(model.videoFormatText == ".mp4" && model.videoContentType == .mpeg4Movie)
        #expect(model.isVideoCodecSelectable && model.canExportVideo)
        #expect(model.suggestedVideoName().hasSuffix(".mp4"))
        let url = folder.file("clip.mp4")
        await model.exportVideo(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(
            model.notice == UIStrings.videoExported && model.animate.exportProgress == 1 && !model.animate.isExporting)

        model.perform { $0.setBackdropKind(.none) }
        #expect(model.videoFormatText == UIStrings.movWithAlpha && !model.isVideoCodecSelectable)
        #expect(model.videoContentType == .quickTimeMovie)
        model.setVideoOptions { $0.resolution = .twoK }
        let cancelled = folder.file("cancelled.mov")
        let export = Task { await model.exportVideo(to: cancelled) }
        while !model.animate.isExporting { await Task.yield() }
        #expect(!model.canExportVideo)
        model.cancelVideoExport()
        await export.value
        #expect(model.notice == UIStrings.videoExportCancelled && !model.animate.isExporting)
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
    }

    @Test("[S13-AC18] [S13-AC19] menus: Animate ⇧⌘M, Import Video… ⌥⌘I, Export Video… ⌃⌘E; copy for the UI")
    func menus() async throws {
        #expect(MenuCatalog.title(.animate) == "Animate" && MenuCatalog.shortcut(.animate)?.description == "⇧⌘M")
        #expect(MenuCatalog.shortcut(.importVideo)?.description == "⌥⌘I")
        #expect(MenuCatalog.shortcut(.exportVideo)?.description == "⌃⌘E")
        #expect(MenuCatalog.title(.exportVideo) == UIStrings.exportVideo)
        #expect(MenuCatalog.title(.importVideo) == UIStrings.importVideo)
        #expect(MenuCatalog.clashes.isEmpty)
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        #expect(!controller.isEnabled(.exportVideo) && !controller.isEnabled(.animate))
        await controller.model.importData(try TestImages.png())
        #expect(controller.isEnabled(.exportVideo) && controller.isEnabled(.animate))
        #expect(controller.menuTitle(.animate) == UIStrings.animate)
        controller.model.toggleAnimateMode()
        #expect(controller.menuTitle(.animate) == UIStrings.exitAnimate)
        #expect(
            AnimationEasing.allCases.map(UIStrings.easingLabel) == [
                "Spring", "Linear", "Cubic", "Out", "In Out", "Out Circ",
            ])
        #expect(UIStrings.milliseconds(1000) == "1000ms")
        let clip = AnimationClip(target: ContentTransform(zoom: 120), durationMS: 0)
        #expect(UIStrings.clipAccessibility(index: 0, clip: clip) == "Animation 1: Jump cut, zoom 120 %")
    }
}
