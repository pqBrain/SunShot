public import SunshotCore

/// S14: batch import, preview strip and batch export copy.
extension UIStrings {
    public static let importMultiple = "Import Multiple…"
    public static let exportAll = "Export All…"
    public static let closeBatch = "Close Batch"
    public static let sharedStyleHint = "One style for every image"
    public static let done = "Done"
    public static let showInFinder = "Show in Finder"
    public static let moveLeft = "Move Left"
    public static let moveRight = "Move Right"
    public static let removeFromBatch = "Remove from Batch"
    public static let exportHere = "Export Here"
    public static let chooseExportFolder = "Choose a folder for the exported images"
    public static let importMultiplePrompt = "Add to Batch"
    public static let batchStripAccessibility = "Batch images"
    public static let exportAllAccessibility = "Export all images in the batch, ⌥⇧⌘E"

    /// `12 images`.
    public static func imageCount(_ count: Int) -> String { count == 1 ? "1 image" : "\(count) images" }

    /// `Exporting 3 of 12`.
    public static func exportingProgress(_ progress: BulkProgress) -> String {
        "Exporting \(min(progress.completed + 1, progress.total)) of \(progress.total)"
    }

    /// `Exported 12 images`, `Exported 3 of 5 — 2 failed`, `Cancelled — exported 3 of 10`.
    public static func exportSummary(_ report: BulkReport) -> String {
        let written = report.written.count
        if report.wasCancelled { return "Cancelled — exported \(written) of \(report.total)" }
        if report.failures.isEmpty { return "Exported \(imageCount(written))" }
        return "Exported \(written) of \(report.total) — \(report.failures.count) failed"
    }

    /// `shot.png: The file is damaged or isn't an image.`
    public static func failureLine(_ failure: BulkFailure) -> String { "\(failure.name): \(failure.reason)" }

    /// VoiceOver label of a strip thumbnail: `Image 2 of 12, shot.png, selected`.
    public static func batchItemLabel(
        name: String, index: Int, count: Int, isSelected: Bool, hasError: Bool
    ) -> String {
        var parts = ["Image \(index + 1) of \(count)", name]
        if hasError { parts.append("can't open") }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    /// Notice after adding files to a batch; nil when everything offered was added.
    public static func batchAddNotice(_ result: BulkAddResult, skipped: Int) -> String? {
        var parts: [String] = []
        if skipped > 0 {
            parts.append(
                skipped == 1
                    ? "Skipped 1 file that isn't a supported image"
                    : "Skipped \(skipped) files that aren't supported images")
        }
        if result.duplicates > 0 {
            parts.append(
                result.duplicates == 1
                    ? "1 image was already in the batch" : "\(result.duplicates) images were already in the batch")
        }
        if result.overLimit > 0 {
            parts.append("A batch holds up to \(BulkBatch.maxItems) images; \(result.overLimit) weren't added")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    /// `Can't open shot.png: The file is damaged or isn't an image.`
    public static func cantOpenBatchItem(_ name: String, reason: String) -> String { "Can't open \(name): \(reason)" }
}
