public import Foundation
public import SunshotCore

/// S18 copy: Check for Updates…, the update alert and the Updates rows in Settings.
extension UIStrings {
    public static let checkForUpdates = "Check for Updates…"
    public static let checkNow = "Check Now"
    public static let updatesSection = "Updates"
    public static let checkAutomaticallySetting = "Check for updates automatically"
    public static let checkAutomaticallyHint =
        "Once a day Sunshot asks GitHub for the latest version number. Nothing about you or your documents is sent."
    public static let checkingForUpdates = "Checking for updates…"
    public static let neverChecked = "Not checked yet"

    // Alert
    public static func updateAvailableTitle(_ version: AppVersion) -> String { "Sunshot \(version) is available" }
    public static func updateAvailableMessage(current: String, release: ReleaseInfo) -> String {
        let intro =
            "You have \(current). Download the new version from its release page and replace Sunshot in "
            + "Applications."
        let notes = release.notesExcerpt()
        return notes.isEmpty ? intro : intro + "\n\n" + notes
    }
    public static let download = "Download"
    public static let skipThisVersion = "Skip This Version"
    public static let later = "Later"
    public static let ok = "OK"
    public static let upToDateTitle = "You're up to date"
    public static func upToDateMessage(current: String) -> String {
        "Sunshot \(current) is the newest version."
    }
    public static let noReleasesTitle = "No releases yet"
    public static let noReleasesMessage = "No Sunshot release has been published yet. Check again later."
    public static let checkFailedTitle = "Couldn't check for updates"
    public static let checkFailedMessage = "Sunshot couldn't reach GitHub. Check your connection and try again."

    /// The Updates row in Settings ▸ About and the menu bar menu: what the last check found and when.
    public static func updateStatus(_ state: UpdateChecker.State, lastCheck: Date?, now: Date = Date()) -> String {
        switch state {
        case .checking:
            return checkingForUpdates
        case .finished(let outcome, let date):
            let when = checkedTime(date, now: now)
            switch outcome {
            case .upToDate: return "Up to date · checked \(when)"
            case .available(let release): return "Sunshot \(release.version) is available"
            case .noReleases: return "No releases yet · checked \(when)"
            case .failed: return "Couldn't check · \(when)"
            }
        case .idle:
            guard let lastCheck else { return neverChecked }
            return "Last checked \(checkedTime(lastCheck, now: now))"
        }
    }

    static func checkedTime(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
