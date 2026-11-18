import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// S18: Sunshot ▸ Check for Updates… (after About Sunshot).
struct UpdateCommands: Commands {
    let updates: UpdateChecker

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(MenuCatalog.title(.checkForUpdates)) { Self.checkNow(updates) }
                .disabled(updates.state == .checking)
        }
    }

    @MainActor
    static func checkNow(_ updates: UpdateChecker) {
        Task { await updates.check(userInitiated: true) }
    }
}

/// S18: what a check found, as an alert. A new version offers Download (its release page), Later and Skip This
/// Version; the other answers only show for a check the user asked for (`UpdatePolicy.shouldAnnounce`).
@MainActor
enum UpdateAlerts {
    static func show(_ outcome: UpdateOutcome, userInitiated: Bool, checker: UpdateChecker) {
        NSApp.activate()
        let alert = NSAlert()
        switch outcome {
        case .available(let release):
            alert.messageText = UIStrings.updateAvailableTitle(release.version)
            alert.informativeText = UIStrings.updateAvailableMessage(current: checker.currentVersion, release: release)
            alert.addButton(withTitle: UIStrings.download)
            alert.addButton(withTitle: UIStrings.later)
            alert.addButton(withTitle: UIStrings.skipThisVersion)
            switch alert.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(release.pageURL)
            case .alertThirdButtonReturn: checker.skip(release.version)
            default: break
            }
            return
        case .upToDate:
            alert.messageText = UIStrings.upToDateTitle
            alert.informativeText = UIStrings.upToDateMessage(current: checker.currentVersion)
        case .noReleases:
            alert.messageText = UIStrings.noReleasesTitle
            alert.informativeText = UIStrings.noReleasesMessage
        case .failed:
            alert.alertStyle = .warning
            alert.messageText = UIStrings.checkFailedTitle
            alert.informativeText = UIStrings.checkFailedMessage
        }
        alert.addButton(withTitle: UIStrings.ok)
        alert.runModal()
    }
}

/// S18: Settings ▸ About ▸ Updates: the last check's result, Check Now and the automatic-check switch.
struct UpdatesCard: View {
    @Bindable var controller: DocumentController
    let updates: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UIStrings.updatesSection)
                    Text(UIStrings.updateStatus(updates.state, lastCheck: updates.lastCheck))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updates.state == .checking { ProgressView().controlSize(.small) }
                Button(UIStrings.checkNow) { UpdateCommands.checkNow(updates) }
                    .disabled(updates.state == .checking)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
            Divider()
            Toggle(isOn: $controller.settings.checkForUpdatesAutomatically) {
                Text(UIStrings.checkAutomaticallySetting)
                Text(UIStrings.checkAutomaticallyHint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}
