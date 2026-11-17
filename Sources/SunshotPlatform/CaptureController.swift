import Foundation
public import Observation
public import SunshotCore

/// Capture state for the UI (S10): the capturers (swappable in tests), the website form, the window list, and
/// what is in progress. Edits to the document go through `EditorModel` (see `EditorModel+Capture`).
@MainActor
@Observable
public final class CaptureController {
    public var screen: any ScreenCapturing
    public var web: any WebPageCapturing

    /// Website form (Capture Website…).
    public var websiteText = ""
    public var webOptions = WebCaptureOptions()
    public var showsWebsiteSheet = false
    public internal(set) var isCapturingWebsite = false
    /// Inline error under the address field; cleared when a new capture starts.
    public internal(set) var websiteError: String?

    /// Window picker (Capture Window…).
    public var showsWindowPicker = false
    public internal(set) var windows: [CapturableWindow] = []
    public internal(set) var isCapturingScreen = false

    /// Set when Screen Recording is not allowed: the UI explains it and offers System Settings.
    public var showsPermissionHelp = false

    var websiteTask: Task<Void, Never>?
    /// Identifies the latest website capture, so a cancelled one finishing late changes nothing.
    var websiteGeneration = 0

    public init(screen: any ScreenCapturing = SystemScreenCapturer(), web: (any WebPageCapturing)? = nil) {
        self.screen = screen
        self.web = web ?? WebKitPageCapturer()
    }

    public var canCaptureWebsite: Bool {
        !isCapturingWebsite && !websiteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Runs `operation`, failing with `WebCaptureError.timedOut` when it takes longer than `seconds` (the operation
/// is cancelled). Cancelling the caller cancels the operation.
func withTimeout<T: Sendable>(
    seconds: Double, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw WebCaptureError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw WebCaptureError.timedOut }
        return first
    }
}
