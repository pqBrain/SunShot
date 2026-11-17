/// S13: the video content in a `.sunshot` package. The movie's original bytes are the media file `mediaID`; the
/// document's `content` entry holds its first frame (shown as a still if the movie is missing). Size, length and
/// audio are recorded so opening a document never has to wait for AVFoundation.
public struct VideoEntry: Codable, Hashable, Sendable {
    public var mediaID: String
    public var pixelSize: PixelSize
    /// Length in seconds.
    public var duration: Double
    public var hasAudio: Bool

    public init(mediaID: String, pixelSize: PixelSize, duration: Double, hasAudio: Bool) {
        self.mediaID = mediaID
        self.pixelSize = pixelSize
        self.duration = duration
        self.hasAudio = hasAudio
    }
}
