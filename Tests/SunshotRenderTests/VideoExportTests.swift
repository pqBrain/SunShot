import AVFoundation
import CoreGraphics
import Foundation
import SunshotCore
import Testing

@testable import SunshotRender

/// What an exported movie contains, read back with AVFoundation.
struct MovieInfo {
    var videoTracks = 0
    var audioTracks = 0
    var size = CGSize.zero
    var codec: FourCharCode = 0
    var hasAlpha = false
    var frameRate: Float = 0
    var frames = 0
    var duration = 0.0

    static func read(_ url: URL) async throws -> MovieInfo {
        let asset = AVURLAsset(url: url)
        var info = MovieInfo()
        let videos = try await asset.loadTracks(withMediaType: .video)
        info.videoTracks = videos.count
        info.audioTracks = try await asset.loadTracks(withMediaType: .audio).count
        info.duration = try await asset.load(.duration).seconds
        guard let track = videos.first else { return info }
        info.size = try await track.load(.naturalSize)
        info.frameRate = try await track.load(.nominalFrameRate)
        if let format = try await track.load(.formatDescriptions).first {
            info.codec = CMFormatDescriptionGetMediaSubType(format)
            let alpha = CMFormatDescriptionGetExtension(
                format, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
            info.hasAlpha = (alpha as? Bool) == true || info.codec == kCMVideoCodecType_HEVCWithAlpha
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { info.frames += 1 }
        }
        return info
    }
}

/// Records progress callbacks from the exporter's thread.
final class ProgressLog: @unchecked Sendable {
    // SAFETY: `values` and `onMain` are only touched while `lock` is held.
    private let lock = NSLock()
    private var values: [Double] = []
    private var onMain = false

    func record(_ value: Double) {
        lock.lock()
        values.append(value)
        if Thread.isMainThread { onMain = true }
        lock.unlock()
    }

    var snapshot: (values: [Double], onMain: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (values, onMain)
    }
}

@Suite("Video export")
struct VideoExportTests {
    static let start = ContentTransform(zoom: 90)
    static let end = ContentTransform(x: 0.12, y: -0.05, zoom: 130, rotation: 15)

    /// ≈1 s animation (lead-in 200 ms, 600 ms move, 200 ms hold) on a small canvas.
    static func document(
        backdrop: Backdrop = .solid(RGBAColor(red: 0.95, green: 0.6, blue: 0.2))
    ) throws
        -> EditorDocument
    {
        var project = Project(backdrop: backdrop, padding: 40)
        project.placement.transform = start
        project.timeline = AnimationTimeline(
            clips: [AnimationClip(target: end, durationMS: 600, holdMS: 200, easing: .cubic)], leadInMS: 200)
        project.timeline.video.resolution = .p720
        return EditorDocument(project: project, content: ContentImage(try SampleContent.image(width: 240, height: 140)))
    }

    static func export(_ document: EditorDocument, ext: String) async throws -> (URL, VideoExportPlan) {
        let url = try VideoFixtures.url(ext)
        let plan = try await VideoExporter.export(document, to: url)
        return (url, plan)
    }

    @Test("[S13-AC10] H.264 at 30 fps and HEVC at 60 fps: dimensions, codec, frame rate, frames, duration")
    func mp4Exports() async throws {
        for (codec, rate, fourCC) in [
            (VideoCodec.h264, VideoFrameRate.fps30, kCMVideoCodecType_H264),
            (.hevc, .fps60, kCMVideoCodecType_HEVC),
        ] {
            var document = try Self.document()
            document.project.timeline.video.codec = codec
            document.project.timeline.video.frameRate = rate
            let (url, plan) = try await Self.export(document, ext: "mp4")
            #expect(plan.frameCount == rate.rawValue && plan.height == 720 && plan.encoding.fileExtension == "mp4")
            let info = try await MovieInfo.read(url)
            #expect(info.videoTracks == 1 && info.audioTracks == 0)
            #expect(Int(info.size.width) == plan.width && Int(info.size.height) == plan.height)
            #expect(info.codec == fourCC, "\(codec)")
            #expect(abs(Double(info.frameRate) - Double(rate.rawValue)) < 1)
            #expect(info.frames == plan.frameCount)
            #expect(abs(info.duration - plan.duration) <= 1 / Double(rate.rawValue))
            #expect(!info.hasAlpha)
        }
    }

    @Test("[S13-AC11] first and last exported frames match the renderer at the start and end transforms")
    func framesMatchRenderer() async throws {
        let document = try Self.document()
        let (url, plan) = try await Self.export(document, ext: "mp4")
        let source = try await VideoFrameSource.open(url: url)
        let first = try #require(try source.frame(at: 0))
        let last = try #require(try source.frame(at: plan.duration))
        var startDocument = document
        startDocument.project.animation = nil
        var endDocument = startDocument
        endDocument.project.placement.transform = Self.end
        let expectedFirst = try #require(try Renderer.render(document: startDocument, scale: plan.scale))
        let expectedLast = try #require(try Renderer.render(document: endDocument, scale: plan.scale))
        #expect((first.width, first.height) == (plan.width, plan.height))
        let firstDiff = try VideoFixtures.meanDifference(first, expectedFirst)
        let lastDiff = try VideoFixtures.meanDifference(last, expectedLast)
        #expect(firstDiff <= 6, "first frame differs by \(firstDiff)")
        #expect(lastDiff <= 6, "last frame differs by \(lastDiff)")
        #expect(try VideoFixtures.meanDifference(first, expectedLast) > lastDiff, "frames really moved")
    }

    @Test("[S13-AC12] a see-through backdrop exports HEVC with alpha in a .mov")
    func transparentExport() async throws {
        let document = try Self.document(backdrop: .none)
        let plan = try #require(AnimationRenderer.exportPlan(for: document))
        #expect(plan.encoding == .hevcWithAlpha)
        let (url, _) = try await Self.export(document, ext: plan.encoding.fileExtension)
        let info = try await MovieInfo.read(url)
        #expect(info.hasAlpha && info.videoTracks == 1)
        let frame = try #require(try await VideoFrameSource.open(url: url).frame(at: 0))
        let pixels = try VideoFixtures.pixels(frame, width: frame.width, height: frame.height)
        #expect(pixels[3] < 26, "corner alpha \(pixels[3])")
        let centre = ((frame.height / 2) * frame.width + frame.width / 2) * 4
        #expect(pixels[centre + 3] > 230, "content stays opaque")
    }

    @Test("[S13-AC13] video content's audio is passed through unless muted; frames follow the video")
    func audioPassthrough() async throws {
        let movie = try await VideoFixtures.movie(frameTimes: (0..<20).map { Double($0) / 20 }, end: 1, audio: true)
        var session = EditorSession()
        session.setVideoContent(try await VideoLoader.load(url: movie))
        session.setVideoExportOptions(VideoExportOptions(resolution: .p720))
        let (loud, plan) = try await Self.export(session.document, ext: "mp4")
        let loudInfo = try await MovieInfo.read(loud)
        #expect(loudInfo.audioTracks == 1 && loudInfo.videoTracks == 1)
        #expect(abs(loudInfo.duration - plan.duration) < 0.1)
        let lastFrame = try #require(try await VideoFrameSource.open(url: loud).frame(at: 0.99))
        let firstFrame = try #require(try await VideoFrameSource.open(url: loud).frame(at: 0))
        let middle = ((lastFrame.height / 2) * lastFrame.width + lastFrame.width / 2) * 4
        let lastRed = try VideoFixtures.pixels(lastFrame, width: lastFrame.width, height: lastFrame.height)[middle]
        let firstRed = try VideoFixtures.pixels(firstFrame, width: firstFrame.width, height: firstFrame.height)[middle]
        #expect(Int(lastRed) - Int(firstRed) > 150, "the video plays: \(firstRed) → \(lastRed)")

        session.setMuted(true)
        let (quiet, _) = try await Self.export(session.document, ext: "mp4")
        let quietInfo = try await MovieInfo.read(quiet)
        #expect(quietInfo.audioTracks == 0 && quietInfo.videoTracks == 1)
    }

    @Test("[S13-AC14] progress rises to 1 off the main thread; cancel stops and leaves no file")
    func progressAndCancel() async throws {
        let document = try Self.document()
        let log = ProgressLog()
        let url = try VideoFixtures.url("mp4")
        try await VideoExporter.export(document, to: url) { log.record($0) }
        let (values, onMain) = log.snapshot
        #expect(values.first.map { $0 > 0 } == true && values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(!onMain)

        var long = document
        long.project.timeline.clips[0].holdMS = 10_000
        let cancelled = try VideoFixtures.url("mp4")
        let cancelLog = ProgressLog()
        let task = Task.detached { try await VideoExporter.export(long, to: cancelled) { cancelLog.record($0) } }
        while cancelLog.snapshot.values.count < 3 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let framesAfterCancel = cancelLog.snapshot.values.count
        #expect(framesAfterCancel < 300)
        #expect(!FileManager.default.fileExists(atPath: cancelled.path))
        await #expect(throws: VideoExportError.noContent) { try await VideoExporter.export(EditorDocument(), to: url) }
        #expect(FileManager.default.fileExists(atPath: url.path), "a failed export never touches an existing file")
        #expect(!VideoExportError.encoderUnavailable.reason.isEmpty && !VideoExportError.noContent.reason.isEmpty)
        #expect(VideoExportError.writeFailed("x").reason.contains("x"))
    }

    @Test("[S13-AC16] timeline and video are saved in the package and reopen; a missing movie is reported")
    func packageRoundTrip() async throws {
        let movie = try await VideoFixtures.movie(frameTimes: (0..<10).map { Double($0) / 10 }, end: 1, audio: true)
        var session = EditorSession()
        session.setVideoContent(try await VideoLoader.load(url: movie))
        let clip = session.addClip(at: 0)
        session.setClipEasing(id: clip, .inOut)
        session.setMuted(true)
        session.setVideoExportOptions(VideoExportOptions(resolution: .twoK, frameRate: .fps60, codec: .hevc))
        let package = try VideoFixtures.url(DocumentPackage.fileExtension)
        try DocumentPackage.write(session.document, to: package)

        let loaded = try DocumentPackage.read(from: package).document
        #expect(loaded.project.timeline == session.document.project.timeline)
        let video = try #require(loaded.activeVideo)
        let original = try #require(session.document.activeVideo)
        #expect(video.id == original.id && video.pixelSize == original.pixelSize && video.hasAudio)
        #expect(abs(video.duration - original.duration) < 1e-9)
        #expect(try Data(contentsOf: video.url) == Data(contentsOf: movie))
        #expect(try await VideoFrameSource.open(url: video.url).frame(at: 0.5) != nil)
        let manifest = try DocumentManifestCodec.decode(
            Data(contentsOf: package.appendingPathComponent(DocumentManifest.fileName))
        ).manifest
        let entry = try #require(manifest.video)
        #expect(manifest.media.contains { $0.id == entry.mediaID && $0.path.hasSuffix(".mov") })

        let mediaPath = try #require(manifest.media.first { $0.id == entry.mediaID }?.path)
        try FileManager.default.removeItem(at: package.appendingPathComponent(mediaPath))
        #expect(throws: DocumentFormatError.self) { try DocumentPackage.read(from: package) }
        let placeholder = try DocumentPackage.read(from: package, allowPlaceholders: true)
        #expect(placeholder.document.activeVideo == nil && placeholder.document.content != nil)
        #expect(placeholder.placeholders.count == 1)
    }
}
