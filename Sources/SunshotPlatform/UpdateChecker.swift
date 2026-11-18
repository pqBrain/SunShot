public import Foundation
public import Observation
public import SunshotCore
import os

/// S18: asks the release feed whether a newer Sunshot is published. Sunshot ▸ Check for Updates… asks now; the
/// automatic check asks at most once a day while Settings ▸ Check for updates automatically is on. Only the version
/// question is sent (a plain GET with a `Sunshot/<version>` user agent): no identifiers, documents or settings.
@MainActor
@Observable
public final class UpdateChecker {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum State: Equatable, Sendable {
        case idle
        case checking
        case finished(UpdateOutcome, at: Date)
    }

    public private(set) var state: State = .idle
    /// The last check that reached the feed (a failed one is retried, so it isn't recorded).
    public private(set) var lastCheck: Date?
    /// "Skip This Version": automatic checks stay quiet about this version (a check the user asks for still shows it).
    public private(set) var skippedVersion: AppVersion?
    /// The outcomes the user should see: every answer to a check they asked for, and a new version found by an
    /// automatic one.
    @ObservationIgnored public var onAnnounce: ((UpdateOutcome, _ userInitiated: Bool) -> Void)?

    public let currentVersion: String
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let fetch: Fetch
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var inFlight: Task<UpdateOutcome, Never>?
    @ObservationIgnored private var schedule: Task<Void, Never>?
    nonisolated private static let log = Logger(subsystem: "app.sunshot.Sunshot", category: "update")

    enum Key {
        static let lastCheck = SettingsStore.prefix + "lastUpdateCheck"
        static let skippedVersion = SettingsStore.prefix + "skippedUpdateVersion"
    }

    public init(
        currentVersion: String = AboutInfo.current().version, defaults: UserDefaults = .standard,
        fetch: @escaping Fetch = UpdateChecker.networkFetch, now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        skippedVersion = defaults.string(forKey: Key.skippedVersion).flatMap(AppVersion.init)
    }

    /// The real network: an ephemeral session (no cookies, no cache on disk).
    public static let networkFetch: Fetch = { request in
        try await URLSession(configuration: .ephemeral).data(for: request)
    }

    /// Checks now. A second call while one is running waits for the same answer.
    @discardableResult
    public func check(userInitiated: Bool) async -> UpdateOutcome {
        let task: Task<UpdateOutcome, Never>
        if let inFlight {
            task = inFlight
        } else {
            state = .checking
            let request = request()
            let fetch = fetch
            task = Task { await Self.outcome(of: request, fetch: fetch, current: self.currentVersion) }
            inFlight = task
        }
        let outcome = await task.value
        if inFlight == task { finish(outcome) }
        if UpdatePolicy.shouldAnnounce(outcome, userInitiated: userInitiated, skipped: skippedVersion) {
            onAnnounce?(outcome, userInitiated)
        }
        return outcome
    }

    /// The automatic check: runs only when `enabled` and a day has passed since the last one. Nil when skipped.
    @discardableResult
    public func checkIfDue(enabled: Bool) async -> UpdateOutcome? {
        guard enabled, UpdatePolicy.isDue(lastCheck: lastCheck, now: now()) else { return nil }
        return await check(userInitiated: false)
    }

    /// Keeps checking while the app runs (it can stay in the menu bar for days): now, then every `every` seconds,
    /// each time only if due and `enabled()` says the setting is on.
    public func startAutomaticChecks(every: Duration = .seconds(60 * 60), enabled: @escaping () -> Bool) {
        schedule?.cancel()
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue(enabled: enabled())
                try? await Task.sleep(for: every)
            }
        }
    }

    public func stopAutomaticChecks() {
        schedule?.cancel()
        schedule = nil
    }

    public func skip(_ version: AppVersion) {
        skippedVersion = version
        defaults.set(version.description, forKey: Key.skippedVersion)
    }

    /// The question sent to the feed.
    func request() -> URLRequest {
        var request = URLRequest(
            url: ReleaseFeed.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sunshot/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func finish(_ outcome: UpdateOutcome) {
        inFlight = nil
        let date = now()
        state = .finished(outcome, at: date)
        guard outcome != .failed else { return }
        lastCheck = date
        defaults.set(date, forKey: Key.lastCheck)
    }

    nonisolated static func outcome(of request: URLRequest, fetch: Fetch, current: String) async -> UpdateOutcome {
        do {
            let (data, response) = try await fetch(request)
            return outcome(data: data, response: response, current: current)
        } catch {
            log.info("update check failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// 200 with a release: compare. 404: nothing published yet. Anything else: failed.
    nonisolated static func outcome(data: Data, response: URLResponse, current: String) -> UpdateOutcome {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return .noReleases }
        guard status == 200 else {
            log.info("update check: HTTP \(status, privacy: .public)")
            return .failed
        }
        do {
            return UpdatePolicy.outcome(current: current, latest: try ReleaseFeed.parse(data))
        } catch .notARelease {
            return .noReleases
        } catch {
            log.info("update check: unreadable feed (\(String(describing: error), privacy: .public))")
            return .failed
        }
    }
}
