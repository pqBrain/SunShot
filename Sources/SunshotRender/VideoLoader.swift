import AVFoundation
public import Foundation
import SunshotCore
public import UniformTypeIdentifiers

/// Imports movies as video content: checks the file, copies it into the app's cache (so the document never
/// depends on the original staying put) and decodes the first frame.
public enum VideoLoader {
    /// Movie types offered in the open panel and accepted on drop.
    public static let supportedTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]

    /// Folder holding working copies of imported and opened videos.
    public static var cacheDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SunshotVideo", isDirectory: true)
    }

    public static func isVideoFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    /// Loads the movie at `url`. Throws `VideoLoadError` (nothing is left in the cache on failure).
    public static func load(url: URL, fileName: String? = nil) async throws -> LoadedVideo {
        let id = UUID()
        let copy = try cacheCopy(of: url, id: id)
        do {
            return try await load(cachedURL: copy, id: id, fileName: fileName ?? url.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }

    /// Loads a movie already in the cache (documents being opened).
    static func load(cachedURL url: URL, id: UUID, fileName: String?) async throws -> LoadedVideo {
        let source = try await VideoFrameSource.open(url: url)
        guard source.duration <= AnimationTimeline.maxDuration + 0.05 else {
            throw VideoLoadError.tooLong(source.duration)
        }
        let asset = AVURLAsset(url: url)
        let hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        guard let poster = try source.frame(at: 0) else { throw VideoLoadError.unreadable }
        let video = VideoContent(
            id: id, url: url, posterID: UUID(), pixelSize: PixelSize(width: poster.width, height: poster.height),
            duration: source.duration, hasAudio: hasAudio, fileName: fileName)
        return LoadedVideo(video: video, poster: poster)
    }

    public static func cacheCopy(of url: URL, id: UUID) throws -> URL {
        let target = try cacheURL(id: id, fileExtension: url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            throw VideoLoadError.unreadable
        }
        return target
    }

    public static func cacheURL(id: UUID, fileExtension: String) throws -> URL {
        let folder = cacheDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = fileExtension.isEmpty ? "mov" : fileExtension.lowercased()
        return folder.appendingPathComponent("\(id.uuidString).\(ext)")
    }
}
