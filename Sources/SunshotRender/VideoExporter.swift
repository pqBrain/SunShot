import AVFoundation
import CoreGraphics
import CoreVideo
public import Foundation
public import SunshotCore

public enum VideoExportError: Error, Equatable, Sendable {
    case noContent
    case encoderUnavailable
    case writeFailed(String)

    public var reason: String {
        switch self {
        case .noContent: "There's nothing to export."
        case .encoderUnavailable: "This Mac can't encode this video format."
        case .writeFailed(let detail): "The video couldn't be written (\(detail))."
        }
    }
}

/// Writes an animation as a movie with `AVAssetWriter`: every frame is `AnimationRenderer.render` (so
/// `Renderer.render(document:)`) drawn into a buffer from the writer's pixel-buffer pool, so memory stays flat
/// however long the export. Video content's audio is passed through unless muted. The movie is written to a
/// temporary file and moved into place at the end; a cancelled or failed export leaves nothing at `url`.
public enum VideoExporter {
    /// Exports `document` to `url`. `progress` gets 0…1 after each frame. Throws `CancellationError` when the
    /// calling task is cancelled. Runs on the caller's (non-main) executor.
    @discardableResult
    public static func export(
        _ document: EditorDocument, to url: URL, progress: @Sendable (Double) -> Void = { _ in }
    ) async throws -> VideoExportPlan {
        guard let plan = AnimationRenderer.exportPlan(for: document) else { throw VideoExportError.noContent }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("sunshot-export-\(UUID().uuidString).\(plan.encoding.fileExtension)")
        do {
            try await write(document, plan: plan, to: temporary, progress: progress)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            return plan
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func write(
        _ document: EditorDocument, plan: VideoExportPlan, to url: URL, progress: @Sendable (Double) -> Void
    ) async throws {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: plan.encoding.hasAlpha ? .mov : .mp4)
        } catch {
            throw VideoExportError.writeFailed(error.localizedDescription)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(plan))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw VideoExportError.encoderUnavailable }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: plan.width, kCVPixelBufferHeightKey as String: plan.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ])
        let video = document.activeVideo
        let audio = document.project.timeline.isMuted ? nil : try await AudioPassthrough.make(video, writer: writer)
        var frames: VideoFrameSource?
        if let video { frames = try await VideoFrameSource.open(url: video.url) }

        guard writer.startWriting() else {
            throw VideoExportError.writeFailed(writer.error?.localizedDescription ?? "start failed")
        }
        writer.startSession(atSourceTime: .zero)
        do {
            for index in 0..<plan.frameCount {
                try Task.checkCancellation()
                let time = plan.time(ofFrame: index)
                let buffer = try await pooledBuffer(adaptor, writer: writer)
                try autoreleasepool { try renderFrame(document, at: time, frames: frames, plan: plan, into: buffer) }
                try await waitUntilReady(input, writer: writer) { audio?.pump(until: plan.time(ofFrame: index + 1)) }
                guard
                    adaptor.append(
                        buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(plan.fps)))
                else { throw VideoExportError.writeFailed(writer.error?.localizedDescription ?? "frame rejected") }
                audio?.pump(until: plan.time(ofFrame: index + 1))
                progress(Double(index + 1) / Double(plan.frameCount))
            }
            input.markAsFinished()
            try await audio?.finish(until: plan.duration, writer: writer)
        } catch {
            writer.cancelWriting()
            throw error
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(plan.frameCount), timescale: Int32(plan.fps)))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw VideoExportError.writeFailed(writer.error?.localizedDescription ?? "finish failed")
        }
    }

    static func videoSettings(_ plan: VideoExportPlan) -> [String: Any] {
        let codec: AVVideoCodecType =
            switch plan.encoding {
            case .h264: .h264
            case .hevc: .hevc
            case .hevcWithAlpha: .hevcWithAlpha
            }
        return [
            AVVideoCodecKey: codec, AVVideoWidthKey: plan.width, AVVideoHeightKey: plan.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: plan.fps, AVVideoMaxKeyFrameIntervalKey: plan.fps,
            ],
        ]
    }

    /// Frames handed to the encoder but not yet encoded. The encoder queues as many frames as it is given, so
    /// the pool refuses more than this and the export waits: memory stays flat whatever the length.
    static let maxBuffersInFlight = 6

    /// A buffer from the writer's pool, waiting while `maxBuffersInFlight` are still with the encoder.
    static func pooledBuffer(
        _ adaptor: AVAssetWriterInputPixelBufferAdaptor, writer: AVAssetWriter
    ) async throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw VideoExportError.writeFailed("no pixel buffer pool") }
        let limit = [kCVPixelBufferPoolAllocationThresholdKey as String: maxBuffersInFlight] as CFDictionary
        while true {
            var created: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, limit, &created)
            if let created { return created }
            guard status == kCVReturnWouldExceedAllocationThreshold, writer.status == .writing else {
                throw VideoExportError.writeFailed("no pixel buffer (\(status))")
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Renders one frame into `buffer` (top-left aligned; a 1 px odd remainder is cropped).
    static func renderFrame(
        _ document: EditorDocument, at time: Double, frames: VideoFrameSource?, plan: VideoExportPlan,
        into buffer: CVPixelBuffer
    ) throws {
        let videoFrame = try frames?.frame(at: time)
        guard let image = try AnimationRenderer.render(document, at: time, videoFrame: videoFrame, scale: plan.scale)
        else { throw VideoExportError.noContent }
        CVBufferSetAttachment(
            buffer, kCVImageBufferAlphaChannelModeKey, kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
            .shouldPropagate)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: plan.width, height: plan.height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { throw RenderError.contextCreationFailed }
        context.clear(CGRect(x: 0, y: 0, width: plan.width, height: plan.height))
        context.draw(
            image,
            in: CGRect(x: 0, y: plan.height - image.height, width: image.width, height: image.height))
    }

    /// Longest the writer may refuse data before the export fails instead of hanging.
    static let stallTimeout: Duration = .seconds(30)

    /// Waits until `input` takes data. `whileWaiting` runs on each poll (feeds the other input, which the writer
    /// may be waiting on to interleave).
    static func waitUntilReady(
        _ input: AVAssetWriterInput, writer: AVAssetWriter, whileWaiting: () -> Void = {}
    ) async throws {
        let deadline = ContinuousClock.now + stallTimeout
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if writer.status == .failed {
                throw VideoExportError.writeFailed(writer.error?.localizedDescription ?? "writer failed")
            }
            guard ContinuousClock.now < deadline else { throw VideoExportError.writeFailed("the writer stalled") }
            whileWaiting()
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
