import Foundation
import SunshotCore

/// S13: video content in `.sunshot` packages. The movie's original bytes go to `media/<id>.<ext>` (memory-mapped
/// when saving), the manifest's `video` entry points at it, and opening copies it to the video cache.
extension DocumentPackage {
    /// The movie's media entry, manifest entry and bytes, or nil when the document has no video content.
    static func videoFile(
        for document: EditorDocument
    ) throws -> (media: MediaEntry, entry: VideoEntry, data: Data)? {
        guard let video = document.activeVideo else { return nil }
        let data = try Data(contentsOf: video.url, options: .mappedIfSafe)
        let id = video.id.uuidString
        let ext = video.url.pathExtension.isEmpty ? "mov" : video.url.pathExtension
        let path = DocumentManifestCodec.mediaPath(id: id, fileExtension: ext)
        let entry = VideoEntry(
            mediaID: id, pixelSize: video.pixelSize, duration: video.duration, hasAudio: video.hasAudio)
        return (MediaEntry(id: id, path: path, fileName: video.fileName), entry, data)
    }

    /// Attaches the manifest's video to `document` (whose content must already be its first frame). Returns the
    /// names of missing movies (only when placeholders are allowed: the still frame stays as image content).
    static func readVideo(
        _ manifest: DocumentManifest, root: URL, into document: inout EditorDocument, allowPlaceholders: Bool
    ) throws -> [String] {
        guard let entry = manifest.video, let poster = document.content else { return [] }
        guard let media = manifest.media.first(where: { $0.id == entry.mediaID }) else {
            if allowPlaceholders { return [entry.mediaID] }
            throw DocumentFormatError.missingMedia([entry.mediaID])
        }
        let file = try contained(media.path, in: root)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        let id = UUID(uuidString: entry.mediaID) ?? UUID()
        guard let size, size > 0, let copy = try? VideoLoader.cacheCopy(of: file, id: UUID()) else {
            if allowPlaceholders { return [media.fileName ?? media.path] }
            throw DocumentFormatError.missingMedia([media.fileName ?? media.path])
        }
        document.video = VideoContent(
            id: id, url: copy, posterID: poster.id, pixelSize: entry.pixelSize,
            duration: min(max(entry.duration, 0), AnimationTimeline.maxDuration), hasAudio: entry.hasAudio,
            fileName: media.fileName)
        return []
    }
}
