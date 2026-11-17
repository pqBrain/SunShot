import AVFoundation
import Foundation

/// Copies the video content's audio into the export without re-encoding, interleaved with the video frames
/// (`pump` after each frame appends the audio up to that frame's end, never blocking).
final class AudioPassthrough {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let input: AVAssetWriterInput
    private var pending: CMSampleBuffer?
    private var isDone = false
    private var isFinished = false

    private init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        self.reader = reader
        self.output = output
        self.input = input
    }

    /// A passthrough for `video`'s first audio track added to `writer`, or nil when there is no audio (or the
    /// container can't take it as is: the export is then silent).
    static func make(_ video: VideoContent?, writer: AVAssetWriter) async throws -> AudioPassthrough? {
        guard let video, video.hasAudio else { return nil }
        let asset = AVURLAsset(url: video.url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
            let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let hint = (try? await track.load(.formatDescriptions))?.first
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(output), writer.canAdd(input) else { return nil }
        reader.add(output)
        writer.add(input)
        guard reader.startReading() else {
            input.markAsFinished()
            return nil
        }
        return AudioPassthrough(reader: reader, output: output, input: input)
    }

    /// Appends audio that starts before `time` seconds while the writer accepts it.
    func pump(until time: Double) {
        while !isDone {
            if pending == nil {
                pending = output.copyNextSampleBuffer()
                if pending == nil {
                    // Close the input as soon as the audio runs out: the writer interleaves its inputs and would
                    // otherwise hold the video back waiting for audio that never comes.
                    close()
                    break
                }
            }
            guard let sample = pending else { break }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if start >= time || !input.isReadyForMoreMediaData { break }
            pending = nil
            guard input.append(sample) else {
                close()
                break
            }
        }
    }

    private func close() {
        isDone = true
        guard !isFinished else { return }
        isFinished = true
        reader.cancelReading()
        input.markAsFinished()
    }

    /// Appends the rest of the audio up to `time` (waiting for the writer), then closes the input.
    func finish(until time: Double, writer: AVAssetWriter) async throws {
        while !isDone {
            try await VideoExporter.waitUntilReady(input, writer: writer)
            pump(until: time)
            if let sample = pending, CMSampleBufferGetPresentationTimeStamp(sample).seconds >= time { break }
        }
        close()
    }
}
