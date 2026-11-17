public import Foundation
public import SunshotCore
import SunshotRender
public import UniformTypeIdentifiers

/// S13: importing video content and exporting the animation as a movie.
extension EditorModel {
    public static let videoExportFailedTitle = "Couldn't export the video"

    // MARK: Import

    /// Loads a movie as the content (one undo step); on failure shows an alert and leaves the document untouched.
    public func importVideo(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try await VideoLoader.load(url: url)
            session.setVideoContent(loaded)
            animate.playhead = 0
            await refreshPreview()
        } catch {
            let reason = (error as? VideoLoadError)?.reason ?? error.localizedDescription
            alert = AlertContent(title: Self.openFailedTitle, message: "\(url.lastPathComponent): \(reason)")
        }
    }

    // MARK: Export options

    public var videoOptions: VideoExportOptions { timeline.video }

    public func setVideoOptions(_ change: (inout VideoExportOptions) -> Void) {
        var options = videoOptions
        change(&options)
        perform { $0.setVideoExportOptions(options) }
    }

    public var videoExportPlan: VideoExportPlan? { AnimationRenderer.exportPlan(for: session.document) }

    /// See-through backdrops always export HEVC with alpha, so the codec picker is disabled for them.
    public var isVideoCodecSelectable: Bool { !project.hasTransparentBackdrop }

    public var videoResolutionText: String {
        guard let plan = videoExportPlan else { return "—" }
        return UIStrings.pixelSize(width: plan.width, height: plan.height)
    }

    public var videoDurationText: String { TimecodeFormat.short(videoExportPlan?.duration ?? 0) }

    public var videoFormatText: String {
        guard let plan = videoExportPlan else { return ".mp4" }
        return plan.encoding.hasAlpha ? UIStrings.movWithAlpha : ".\(plan.encoding.fileExtension)"
    }

    public var videoContentType: UTType {
        videoExportPlan.flatMap { UTType($0.encoding.typeIdentifier) } ?? .mpeg4Movie
    }

    public var canExportVideo: Bool { hasContent && !animate.isExporting }

    /// File name for the save panel: the image name from the template with the movie's extension.
    public func suggestedVideoName(now: Date = Date()) -> String {
        let base = (suggestedExportName(now: now) as NSString).deletingPathExtension
        return "\(base).\(videoExportPlan?.encoding.fileExtension ?? "mp4")"
    }

    // MARK: Export

    /// Exports the animation to `url` off the main actor, updating `animate.exportProgress`. Cancelling
    /// (`cancelVideoExport`) stops it and leaves nothing at `url`; failures show an alert.
    public func exportVideo(to url: URL) async {
        guard canExportVideo else { return }
        let document = session.document
        animate.isExporting = true
        animate.exportProgress = 0
        let work = Task.detached(priority: .userInitiated) { [weak self] in
            _ = try await VideoExporter.export(document, to: url) { value in
                Task { @MainActor in
                    guard let self, self.animate.isExporting else { return }
                    self.animate.exportProgress = max(self.animate.exportProgress, value)
                }
            }
        }
        animate.exportWork = work
        do {
            try await work.value
            animate.exportProgress = 1
            notice = UIStrings.videoExported
            animate.showsExportSheet = false
        } catch is CancellationError {
            notice = UIStrings.videoExportCancelled
        } catch {
            let reason = (error as? VideoExportError)?.reason ?? error.localizedDescription
            alert = AlertContent(title: Self.videoExportFailedTitle, message: reason)
        }
        animate.exportWork = nil
        animate.isExporting = false
    }

    public func cancelVideoExport() {
        animate.exportWork?.cancel()
    }
}
