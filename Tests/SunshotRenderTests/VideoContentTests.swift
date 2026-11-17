import CoreGraphics
import Foundation
import ImageIO
import SunshotCore
import Testing

@testable import SunshotRender

@Suite("Video content and animation editing")
struct VideoContentTests {
    static func imageSession() throws -> EditorSession {
        var session = EditorSession()
        session.setContent(try SampleContent.image(width: 200, height: 120))
        return session
    }

    @Test("[S13-AC7] a movie imports as content: first frame, size, duration, audio; one undo step")
    func importVideo() async throws {
        let url = try await VideoFixtures.movie(frameTimes: (0..<15).map { Double($0) / 15 }, end: 1, audio: true)
        let loaded = try await VideoLoader.load(url: url)
        #expect(loaded.video.pixelSize == PixelSize(width: 160, height: 90))
        #expect(abs(loaded.video.duration - 1) < 0.05 && loaded.video.hasAudio)
        #expect(loaded.video.url != url && FileManager.default.fileExists(atPath: loaded.video.url.path))
        #expect(loaded.video.url.path.hasPrefix(VideoLoader.cacheDirectory.path))
        #expect(loaded.video.fileName == url.lastPathComponent)
        #expect(VideoLoader.isVideoFile(url) && !VideoLoader.isVideoFile(URL(fileURLWithPath: "/a.png")))

        var session = try Self.imageSession()
        session.setVideoContent(loaded)
        #expect(session.document.activeVideo == loaded.video)
        #expect(session.document.content?.id == loaded.video.posterID)
        #expect(session.document.contentPixelSize == PixelSize(width: 160, height: 90))
        #expect(session.history.undoNames.last == EditorSession.importVideoActionName)
        session.undo()
        #expect(session.document.activeVideo == nil)
        session.redo()
        session.setContent(try SampleContent.image(width: 50, height: 50))
        #expect(session.document.activeVideo == nil, "a later image replaces the video")
    }

    @Test("[S13-AC7] a file without video is refused and leaves nothing in the cache")
    func noVideoTrack() async throws {
        let audioOnly = try await VideoFixtures.movie(frameTimes: [], end: 0.5, audio: true)
        await #expect(throws: VideoLoadError.noVideoTrack) { try await VideoLoader.load(url: audioOnly) }
        #expect(VideoLoadError.noVideoTrack.reason == "This file has no video")
        let notAMovie = try VideoFixtures.url("mov")
        try Data("hello".utf8).write(to: notAMovie)
        await #expect(throws: VideoLoadError.self) { try await VideoLoader.load(url: notAMovie) }
        await #expect(throws: VideoLoadError.unreadable) {
            try await VideoLoader.load(url: URL(fileURLWithPath: "/nonexistent/clip.mov"))
        }
        #expect(!VideoLoadError.unreadable.reason.isEmpty)
    }

    @Test("[S13-AC6] a movie longer than two minutes is refused")
    func tooLong() async throws {
        let url = try await VideoFixtures.movie(frameTimes: [0, 121], end: 121.5)
        await #expect(throws: VideoLoadError.tooLong(121.5)) { try await VideoLoader.load(url: url) }
        #expect(VideoLoadError.tooLong(130).reason == "Videos can be at most 2 minutes long")
    }

    @Test("[S13-AC8] video frames are read in order, by time, holding the last frame after the end")
    func frameSource() async throws {
        let url = try await VideoFixtures.movie(frameTimes: (0..<30).map { Double($0) / 10 }, end: 3)
        let source = try await VideoFrameSource.open(url: url)
        #expect(abs(source.duration - 3) < 0.01)
        func red(at time: Double) throws -> Int {
            guard let image = try source.frame(at: time) else { return -1 }
            return Int(try VideoFixtures.pixels(image, width: image.width, height: image.height)[0])
        }
        // Sequential decode gives each frame's colour (codec colour conversion shifts values; order is what counts).
        let reds = try (0..<30).map { try red(at: Double($0) / 10) }
        #expect(zip(reds, reds.dropFirst()).allSatisfy { $0 < $1 }, "\(reds)")
        for (time, index) in [(0.0, 0), (0.55, 5), (1.0, 10), (2.95, 29), (10, 29), (0.2, 2), (2.5, 25), (0.04, 0)] {
            #expect(try red(at: time) == reds[index], "t=\(time)")
        }
        #expect(VideoFrameSource.orientation(of: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)) == .right)
        #expect(VideoFrameSource.orientation(of: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) == .left)
        #expect(VideoFrameSource.orientation(of: CGAffineTransform(scaleX: -1, y: -1)) == .down)
        #expect(VideoFrameSource.orientation(of: .identity) == .up)
    }

    @Test("[S13-AC8] each animation frame is Renderer.render of the document at that time")
    func frameIsTheRenderer() async throws {
        var session = try Self.imageSession()
        let target = ContentTransform(x: 0.1, zoom: 140, rotation: 12, tiltX: 10)
        session.addClip(at: 0)
        if let id = session.timeline.clips.first?.id { session.setClipTarget(id: id, target) }
        let document = session.document
        let frameDocument = AnimationRenderer.document(document, at: 1.0, videoFrame: nil)
        #expect(
            frameDocument.project.placement.transform == document.project.timeline.transform(at: 1, from: .identity))
        #expect(
            frameDocument.content == document.content && frameDocument.project.backdrop == document.project.backdrop)
        let rendered = try #require(try AnimationRenderer.render(document, at: 1.0, scale: 0.5))
        let direct = try #require(try Renderer.render(document: frameDocument, scale: 0.5))
        #expect(try VideoFixtures.meanDifference(rendered, direct) == 0)
        #expect(AnimationRenderer.duration(of: document) == 2.0)

        let url = try await VideoFixtures.movie(frameTimes: (0..<10).map { Double($0) / 10 }, end: 1)
        session.setVideoContent(try await VideoLoader.load(url: url))
        let video = try #require(session.document.activeVideo)
        let frame = try #require(try await VideoFrameSource.open(url: video.url).frame(at: 0.5))
        let withVideo = AnimationRenderer.document(session.document, at: 0.5, videoFrame: frame)
        #expect(withVideo.content?.image === frame && withVideo.content?.id == video.posterID)
        #expect(AnimationRenderer.duration(of: session.document) == 2.0)
        let still = AnimationRenderer.document(try Self.imageSession().document, at: 0, videoFrame: frame)
        #expect(still.content?.image !== frame, "image content ignores video frames")
        #expect(AnimationRenderer.exportPlan(for: EditorDocument()) == nil)
    }

    @Test("[S13-AC5] clip edits are single named undo steps; no-ops record nothing")
    func clipEditing() throws {
        var session = try Self.imageSession()
        let first = session.addClip(at: 0)
        #expect(session.timeline.clips.count == 1)
        let clip = try #require(session.timeline.clips.first)
        #expect(clip.durationMS == 1000 && clip.easing == .spring && clip.target.zoom == 120)
        let second = session.addClip(at: 1.2)
        #expect(session.timeline.clips.map(\.id) == [first, second])
        #expect(session.timeline.clips[1].target.zoom == 144)
        let early = session.addClip(at: 0.1)
        #expect(session.timeline.clips.map(\.id) == [early, first, second])
        session.moveClip(id: early, by: 5)
        #expect(session.timeline.clips.map(\.id) == [first, second, early])
        session.moveClip(id: early, by: 1)
        session.setClipEasing(id: first, .outCirc)
        session.setClipEasing(id: first, .outCirc)
        session.setClipDuration(id: first, milliseconds: 0)
        session.setClipHold(id: first, milliseconds: 250)
        session.setClipTarget(id: first, ContentTransform(rotation: 45))
        session.setMuted(true)
        session.setMuted(false)
        session.setVideoExportOptions(VideoExportOptions(frameRate: .fps60))
        session.removeClip(id: second)
        session.removeClip(id: UUID())
        #expect(
            session.history.undoNames == [
                "Import Image", "Add Animation", "Add Animation", "Add Animation", "Move Animation", "Change Easing",
                "Change Duration", "Change Hold", "Change Animation Target", "Mute Audio", "Unmute Audio",
                "Change Video Options", "Delete Animation",
            ])
        #expect(session.timeline.clips.first?.isJumpCut == true)
        for _ in 0..<12 { session.undo() }
        #expect(session.document.project.animation == nil)
    }

    @Test("[S13-AC5] a duration slider drag is one undo entry")
    func durationDrag() throws {
        var session = try Self.imageSession()
        let id = session.addClip(at: 0)
        session.beginGesture()
        for value in stride(from: 1000, through: 3000, by: 250) { session.setClipDuration(id: id, milliseconds: value) }
        session.endGesture(EditorSession.clipDurationActionName)
        #expect(session.history.undoNames.suffix(2) == ["Add Animation", "Change Duration"])
        #expect(session.timeline.clips.first?.durationMS == 3000)
    }
}
