public import Foundation

/// S18: what a check for updates found.
public enum UpdateOutcome: Equatable, Sendable {
    /// The running version is the newest published one (or newer: a development build).
    case upToDate(latest: AppVersion)
    case available(ReleaseInfo)
    /// Nothing is published yet.
    case noReleases
    /// Offline, the server failed, or the feed could not be read. Never shown for automatic checks.
    case failed
}

/// S18: when to check and what to tell the user.
public enum UpdatePolicy {
    /// Automatic checks run at most once a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Whether an automatic check is due: never checked, a day has passed, or the clock went backwards.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }

    /// Compares the running version with the latest release. A running version that can't be read (a development
    /// build says `dev`) is never told to update.
    public static func outcome(current: String, latest: ReleaseInfo) -> UpdateOutcome {
        guard let running = AppVersion(current), running < latest.version else {
            return .upToDate(latest: latest.version)
        }
        return .available(latest)
    }

    /// Whether to tell the user about `outcome`. A check the user asked for always answers; an automatic one only
    /// speaks up for a new version the user has not chosen to skip.
    public static func shouldAnnounce(_ outcome: UpdateOutcome, userInitiated: Bool, skipped: AppVersion?) -> Bool {
        if userInitiated { return true }
        guard case .available(let release) = outcome else { return false }
        return release.version != skipped
    }
}
