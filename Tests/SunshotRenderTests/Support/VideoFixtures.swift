import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

@testable import SunshotRender

enum VideoFixtureError: Error { case setup(String) }

/// Movies generated in code (no binary fixtures): solid frames whose red channel encodes the frame index, plus
/// an optional AAC tone.
enum VideoFixtures {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SunshotVideoTests", isDirectory: true)
    }

    static func url(_ ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    /// Red channel of frame `index` of `count` (0…255).
    static func red(index: Int, count: Int) -> Int { count <= 1 ? 0 : index * 255 / (count - 1) }

    /// Writes a QuickTime movie. `frameTimes` are presentation times in seconds (no frames = audio only).
    static func movie(
        width: Int = 160, height: Int = 90, frameTimes: [Double], end: Double, audio: Bool = false
    ) async throws -> URL {
        let url = try url("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var video: (input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor)?
        if !frameTimes.isEmpty {
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                ])
            video = (input, adaptor)
        }
        let tone = audio ? try ToneWriter(writer: writer) : nil
        guard writer.startWriting() else { throw VideoFixtureError.setup("start \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        if let video {
            for (index, time) in frameTimes.enumerated() {
                while !video.input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
                let buffer = try pixelBuffer(
                    width: width, height: height, red: red(index: index, count: frameTimes.count), pool: video.adaptor)
                video.adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
                try await tone?.write(until: index + 1 < frameTimes.count ? frameTimes[index + 1] : end)
            }
            video.input.markAsFinished()
        }
        try await tone?.write(until: end)
        tone?.finish()
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoFixtureError.setup("\(String(describing: writer.error))") }
        return url
    }

    static func pixelBuffer(
        width: Int, height: Int, red: Int, pool adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) }
        guard let buffer = created else { throw VideoFixtureError.setup("pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw VideoFixtureError.setup("base") }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                bytes[offset] = 40  // B
                bytes[offset + 1] = 120  // G
                bytes[offset + 2] = UInt8(red)  // R
                bytes[offset + 3] = 255
            }
        }
        return buffer
    }

    /// Mean absolute channel difference (0…255) between two images of the same size, drawn as sRGB RGBA.
    static func meanDifference(_ lhs: CGImage, _ rhs: CGImage) throws -> Double {
        let left = try pixels(lhs, width: lhs.width, height: lhs.height)
        let right = try pixels(rhs, width: lhs.width, height: lhs.height)
        var total = 0
        for index in 0..<left.count where index % 4 != 3 { total += abs(Int(left[index]) - Int(right[index])) }
        return Double(total) / Double(left.count / 4 * 3)
    }

    /// RGBA bytes of `image` drawn top-left aligned into `width` × `height`.
    static func pixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw VideoFixtureError.setup("context") }
        context.draw(image, in: CGRect(x: 0, y: height - image.height, width: image.width, height: image.height))
        return bytes
    }
}

/// Writes a 440 Hz mono AAC tone, 0.1 s per sample buffer.
final class ToneWriter {
    let input: AVAssetWriterInput
    let format: CMAudioFormatDescription
    var written = 0
    static let rate = 44_100

    init(writer: AVAssetWriter) throws {
        input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.rate, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(Self.rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2,
            mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var created: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &created)
        guard let created else { throw VideoFixtureError.setup("audio format") }
        format = created
    }

    func write(until seconds: Double) async throws {
        let limit = Int(seconds * Double(Self.rate))
        while written < limit {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            let count = min(Self.rate / 10, limit - written)
            var samples = (0..<count).map { index -> Int16 in
                Int16(sin(Double(written + index) * 2 * .pi * 440 / Double(Self.rate)) * 8000)
            }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: count * 2, flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block)
            guard let block else { throw VideoFixtureError.setup("block") }
            CMBlockBufferReplaceDataBytes(
                with: &samples, blockBuffer: block, offsetIntoDestination: 0, dataLength: count * 2)
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                presentationTimeStamp: CMTime(value: Int64(written), timescale: Int32(Self.rate)),
                packetDescriptions: nil, sampleBufferOut: &sample)
            guard let sample else { throw VideoFixtureError.setup("sample") }
            input.append(sample)
            written += count
        }
    }

    func finish() { input.markAsFinished() }
}
