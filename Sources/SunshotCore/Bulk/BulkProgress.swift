public import Foundation

/// Where a batch export is. `completed` counts processed items (written or failed).
public struct BulkProgress: Hashable, Sendable {
    public var total: Int
    public var completed: Int
    public var failed: Int
    /// The file being processed, nil between items and at the end.
    public var currentName: String?

    public init(total: Int, completed: Int = 0, failed: Int = 0, currentName: String? = nil) {
        self.total = total
        self.completed = completed
        self.failed = failed
        self.currentName = currentName
    }

    /// 0…1; 1 for an empty batch.
    public var fractionCompleted: Double { total == 0 ? 1 : Double(completed) / Double(total) }
}

/// One item that couldn't be exported, with a user-facing reason.
public struct BulkFailure: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let reason: String

    public init(id: UUID, name: String, reason: String) {
        self.id = id
        self.name = name
        self.reason = reason
    }
}

/// The outcome of a batch export.
public struct BulkReport: Hashable, Sendable {
    public var total: Int
    public var written: [URL]
    public var failures: [BulkFailure]
    public var wasCancelled: Bool

    public init(total: Int, written: [URL] = [], failures: [BulkFailure] = [], wasCancelled: Bool = false) {
        self.total = total
        self.written = written
        self.failures = failures
        self.wasCancelled = wasCancelled
    }

    /// Items never reached because the export was cancelled.
    public var notProcessed: Int { max(0, total - written.count - failures.count) }
    public var isCompleteSuccess: Bool { !wasCancelled && failures.isEmpty && written.count == total }
}

/// The batch export's state for the UI.
public enum BulkExportState: Hashable, Sendable {
    case idle
    case running(BulkProgress)
    case finished(BulkReport)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
