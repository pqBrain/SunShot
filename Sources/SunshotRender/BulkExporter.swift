public import CoreGraphics
public import Foundation
public import SunshotCore

/// What a batch export needs: the items in export order, the shared style, and where and how to name files.
public struct BulkExportJob: Sendable {
    public var items: [BulkItem]
    public var project: Project
    public var media: [String: MediaAsset]
    public var folder: URL
    public var template: String
    public var templateName: String
    /// One date for the whole run, so `{DATE}` groups the files.
    public var date: Date

    public init(
        items: [BulkItem], project: Project, media: [String: MediaAsset] = [:], folder: URL,
        template: String = SunshotDefaults.filenameTemplate, templateName: String = SunshotDefaults.templateName,
        date: Date = Date()
    ) {
        self.items = items
        self.project = project
        self.media = media
        self.folder = folder
        self.template = template
        self.templateName = templateName
        self.date = date
    }
}

/// Exports every batch item with the shared style, strictly one item at a time (at most one full-size image is
/// decoded at once). A failing item is recorded and the batch goes on; cancelling stops before the next item.
/// Call it off the main actor; cancellation is the calling task's.
public enum BulkExporter {
    public static func run(
        _ job: BulkExportJob,
        loader: (BulkItem) throws -> CGImage = BulkExporter.loadFullImage,
        describe: (any Error) -> String = BulkExporter.describe,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        timeZone: TimeZone = .current,
        progress: (BulkProgress) async -> Void = { _ in }
    ) async -> BulkReport {
        let accessing = job.folder.startAccessingSecurityScopedResource()
        defer { if accessing { job.folder.stopAccessingSecurityScopedResource() } }
        let style = EditorSession(document: EditorDocument(project: job.project, media: job.media))
        var report = BulkReport(total: job.items.count)
        var state = BulkProgress(total: job.items.count)
        var names = BulkNameAllocator()

        for (index, item) in job.items.enumerated() {
            if Task.isCancelled {
                report.wasCancelled = true
                break
            }
            state.currentName = item.displayName
            await progress(state)
            do {
                let url = try autoreleasepool {
                    let image = try loader(item)
                    let (data, plan) = try style.exportData(forBulkImage: image)
                    let context = FilenameContext(
                        templateName: job.templateName, scale: plan.isNativeSize ? .x1 : job.project.export.scale,
                        date: job.date, width: plan.width, height: plan.height, format: job.project.export.format)
                    let proposed = BulkNaming.fileName(
                        template: job.template, index: index, count: job.items.count, sourceName: item.baseName,
                        context: context, timeZone: timeZone)
                    let name = names.claim(proposed) { fileExists(job.folder.appendingPathComponent($0)) }
                    let url = job.folder.appendingPathComponent(name)
                    try FileExport.write(data, to: url)
                    return url
                }
                report.written.append(url)
            } catch {
                report.failures.append(BulkFailure(id: item.id, name: item.displayName, reason: describe(error)))
                state.failed += 1
            }
            state.completed += 1
            state.currentName = nil
            await progress(state)
            await Task.yield()
        }
        return report
    }

    /// Reads and fully decodes an item (S1 rules: orientation, sRGB, truncated files rejected).
    @Sendable
    public static func loadFullImage(_ item: BulkItem) throws -> CGImage {
        let accessing = item.accessURL.startAccessingSecurityScopedResource()
        defer { if accessing { item.accessURL.stopAccessingSecurityScopedResource() } }
        return try ImageLoader.load(try Data(contentsOf: item.url))
    }

    /// One-line reason for a failed item.
    @Sendable
    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as ImageLoadError: return error.reason
        case let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile:
            return "The file no longer exists."
        default: return error.localizedDescription
        }
    }
}
