import AVFoundation
public import CoreGraphics
import CoreImage
public import Foundation
import ImageIO

/// Decodes a movie's frames in presentation order with `AVAssetReader` (one decoded frame in memory at a time,
/// plus one look-ahead). Sequential reads (export, playback) never seek; a jump backwards or far ahead restarts
/// the reader just before the requested time. Used by export and by the preview, so both see the same frames.
// SAFETY: every mutable member (reader, output, current/next frame) is only touched while `lock` is held.
public final class VideoFrameSource: @unchecked Sendable {
    public let duration: Double
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let orientation: CGImagePropertyOrientation
    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: Frame?
    private var next: Frame?
    private var finished = false

    private struct Frame {
        let time: Double
        let image: CGImage
    }

    /// Times within this many seconds count as the same frame.
    static let epsilon = 1e-4
    /// Jumping further ahead than this restarts the reader instead of decoding every frame in between.
    static let seekAheadLimit = 2.0
    /// A restarted reader begins this far before the requested time so the frame showing at it is decoded too.
    static let preroll = 0.25

    init(asset: AVURLAsset, track: AVAssetTrack, duration: Double, orientation: CGImagePropertyOrientation) {
        self.asset = asset
        self.track = track
        self.duration = duration
        self.orientation = orientation
    }

    /// Opens the movie at `url`. Throws `VideoLoadError.noVideoTrack` / `.unreadable`.
    public static func open(url: URL) async throws -> VideoFrameSource {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
            duration = try await asset.load(.duration)
        } catch {
            throw VideoLoadError.unreadable
        }
        guard let track = tracks.first else { throw VideoLoadError.noVideoTrack }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        return VideoFrameSource(
            asset: asset, track: track, duration: max(0, duration.seconds.isFinite ? duration.seconds : 0),
            orientation: Self.orientation(of: transform))
    }

    /// The frame showing at `seconds`: the last frame that starts at or before it (the first frame before the
    /// movie starts, the last one after it ends). Nil only if the movie has no decodable frames.
    public func frame(at seconds: Double) throws -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let time = seconds.isFinite ? max(0, seconds) : 0
        if let current, time + Self.epsilon < current.time || time > current.time + Self.seekAheadLimit {
            try restart(at: time)
        } else if reader == nil {
            try restart(at: time)
        }
        while true {
            if next == nil && !finished { next = readFrame() }
            guard let candidate = next else { break }
            if current == nil || candidate.time <= time + Self.epsilon {
                current = candidate
                next = nil
            } else {
                break
            }
        }
        return current?.image
    }

    private func restart(at time: Double) throws {
        reader?.cancelReading()
        current = nil
        next = nil
        finished = false
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoLoadError.unreadable
        }
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoLoadError.unreadable }
        reader.add(output)
        let start = max(0, min(time, duration) - Self.preroll)
        if start > 0 {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600), end: .positiveInfinity)
        }
        guard reader.startReading() else { throw VideoLoadError.unreadable }
        self.reader = reader
        self.output = output
    }

    private func readFrame() -> Frame? {
        while let output, let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard let image = Self.cgImage(from: buffer, orientation: orientation) else { continue }
            return Frame(time: time.isFinite ? time : 0, image: image)
        }
        finished = true
        return nil
    }

    static func cgImage(from buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGImage? {
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        image = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return ContentTransformRenderer.ciContext.createCGImage(
            image, from: image.extent, format: .RGBA8, colorSpace: space)
    }

    /// The image orientation that displays a track with `transform` upright (90° phone footage etc.).
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
