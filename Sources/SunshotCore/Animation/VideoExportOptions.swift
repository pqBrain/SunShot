/// Output resolution of a video export, by the canvas's shorter side.
public enum VideoResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case p720, hd, twoK

    public var shortSide: Int {
        switch self {
        case .p720: 720
        case .hd: 1080
        case .twoK: 1440
        }
    }

    public var label: String {
        switch self {
        case .p720: "720p"
        case .hd: "HD"
        case .twoK: "2K"
        }
    }
}

public enum VideoFrameRate: Int, Codable, CaseIterable, Hashable, Sendable {
    case fps30 = 30
    case fps60 = 60

    public var label: String { "\(rawValue) fps" }
}

/// Codec the user picks for opaque videos; see-through backdrops always use HEVC with alpha.
public enum VideoCodec: String, Codable, CaseIterable, Hashable, Sendable {
    case h264, hevc

    public var label: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

/// Video export choices, saved with the document's timeline.
public struct VideoExportOptions: Hashable, Sendable {
    public var resolution: VideoResolution
    public var frameRate: VideoFrameRate
    public var codec: VideoCodec

    public init(resolution: VideoResolution = .hd, frameRate: VideoFrameRate = .fps30, codec: VideoCodec = .h264) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
    }
}

extension VideoExportOptions: Codable {
    private enum CodingKeys: String, CodingKey { case resolution, frameRate, codec }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VideoExportOptions()
        resolution =
            ((try? container.decodeIfPresent(VideoResolution.self, forKey: .resolution)) ?? nil) ?? defaults.resolution
        frameRate =
            ((try? container.decodeIfPresent(VideoFrameRate.self, forKey: .frameRate)) ?? nil) ?? defaults.frameRate
        codec = ((try? container.decodeIfPresent(VideoCodec.self, forKey: .codec)) ?? nil) ?? defaults.codec
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(codec, forKey: .codec)
    }
}

/// What the encoder writes.
public enum VideoEncoding: String, Hashable, Sendable {
    case h264, hevc, hevcWithAlpha

    /// `.mp4` for opaque video, `.mov` for HEVC with alpha (MP4 can't carry it).
    public var fileExtension: String { self == .hevcWithAlpha ? "mov" : "mp4" }
    public var typeIdentifier: String { self == .hevcWithAlpha ? "com.apple.quicktime-movie" : "public.mpeg-4" }
    public var hasAlpha: Bool { self == .hevcWithAlpha }
}

/// The resolved video export: pixel size, render scale, frame count and encoding. Pure.
public struct VideoExportPlan: Hashable, Sendable {
    /// Encoders take at most this many pixels per side.
    public static let maxSide = 4096

    public let width: Int
    public let height: Int
    /// Render scale (output pixels per canvas point).
    public let scale: Double
    public let fps: Int
    public let frameCount: Int
    public let encoding: VideoEncoding

    /// Plans an export of `canvasSize` (1×) lasting `duration` seconds.
    public static func make(
        canvasSize: PixelSize, options: VideoExportOptions, duration: Double, transparent: Bool
    ) -> VideoExportPlan {
        let canvasWidth = max(1, canvasSize.width)
        let canvasHeight = max(1, canvasSize.height)
        var scale = Double(options.resolution.shortSide) / Double(min(canvasWidth, canvasHeight))
        scale = min(scale, Double(maxSide) / Double(max(canvasWidth, canvasHeight)))
        func even(_ length: Int) -> Int { max(2, min(maxSide, length) & ~1) }
        let fps = options.frameRate.rawValue
        let seconds = duration.isFinite ? min(max(duration, 0), AnimationTimeline.maxDuration) : 0
        let encoding: VideoEncoding =
            transparent ? .hevcWithAlpha : (options.codec == .hevc ? .hevc : .h264)
        return VideoExportPlan(
            width: even(ExportPlan.scaled(canvasWidth, by: scale)),
            height: even(ExportPlan.scaled(canvasHeight, by: scale)), scale: scale, fps: fps,
            frameCount: max(1, Int((seconds * Double(fps)).rounded())), encoding: encoding)
    }

    public var outputSize: PixelSize { PixelSize(width: width, height: height) }
    /// Length of the written movie in seconds (frame count ÷ fps).
    public var duration: Double { Double(frameCount) / Double(fps) }

    /// Presentation time of frame `index`, in seconds.
    public func time(ofFrame index: Int) -> Double { Double(index) / Double(fps) }
}

/// `00:01.50` (minutes, seconds, hundredths) for the transport bar; `10s` style for the export sheet.
public enum TimecodeFormat {
    public static func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        let hundredths = Int((value * 100).rounded(.down))
        let minutes = hundredths / 6000
        let secs = (hundredths / 100) % 60
        let fraction = hundredths % 100
        return "\(pad(minutes)):\(pad(secs)).\(pad(fraction))"
    }

    public static func short(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths))s" : "\(tenths)s"
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
