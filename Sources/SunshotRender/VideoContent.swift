public import CoreGraphics
public import Foundation
public import SunshotCore

/// Imported video content (S13). The document's `content` holds the video's first frame (the still shown when
/// not playing, with id `posterID`); frames are read from `url` at render time. Identity-compared like
/// `ContentImage`, so undo snapshots never copy the movie.
public struct VideoContent: Equatable, Sendable {
    public let id: UUID
    /// Local copy of the movie (in the app's cache folder), read by AVFoundation.
    public let url: URL
    /// Id of the `ContentImage` holding the first frame; the video is only the content while they match.
    public let posterID: UUID
    /// Display size (orientation applied).
    public let pixelSize: PixelSize
    /// Length in seconds (≤ `AnimationTimeline.maxDuration`).
    public let duration: Double
    public let hasAudio: Bool
    /// The name of the file the user imported, if known.
    public let fileName: String?

    public init(
        id: UUID = UUID(), url: URL, posterID: UUID, pixelSize: PixelSize, duration: Double, hasAudio: Bool,
        fileName: String? = nil
    ) {
        self.id = id
        self.url = url
        self.posterID = posterID
        self.pixelSize = pixelSize
        self.duration = duration
        self.hasAudio = hasAudio
        self.fileName = fileName
    }

    public static func == (lhs: VideoContent, rhs: VideoContent) -> Bool { lhs.id == rhs.id }
}

/// A loaded video: its content record and first frame.
public struct LoadedVideo: Sendable {
    public let video: VideoContent
    public let poster: CGImage
}

public enum VideoLoadError: Error, Equatable, Sendable {
    case unreadable
    case noVideoTrack
    case tooLong(Double)

    public var reason: String {
        switch self {
        case .unreadable: "This file isn't a movie Sunshot can read."
        case .noVideoTrack: "This file has no video"
        case .tooLong: "Videos can be at most 2 minutes long"
        }
    }
}

extension EditorDocument {
    /// The video content, only while the document's content is still that video's first frame (an image or
    /// snippet imported later replaces it without touching `video`).
    public var activeVideo: VideoContent? {
        guard let video, let content, content.id == video.posterID, snippet == nil else { return nil }
        return video
    }
}

extension EditorSession {
    public static let importVideoActionName = "Import Video"

    /// Sets a loaded video as the content (one undo step). The first frame becomes `content`.
    public mutating func setVideoContent(_ loaded: LoadedVideo) {
        history.apply(Self.importVideoActionName) {
            $0.content = ContentImage(loaded.poster, id: loaded.video.posterID)
            $0.snippet = nil
            $0.video = loaded.video
        }
    }
}
