import AppKit
import SunshotPlatform
import SwiftUI

/// Settings ▸ About: icon, name and version, updates (S18), author and system, Copy Diagnostics, privacy and credits.
struct AboutSettingsView: View {
    @Bindable var controller: DocumentController
    let updates: UpdateChecker
    private let info = AboutInfo.current()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                UpdatesCard(controller: controller, updates: updates)
                detailsCard
                privacyCard
                credits
                Text(UIStrings.aboutCopyright(year: Calendar.current.component(.year, from: Date())))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(info.appName).font(.title.bold())
            Text(info.versionLine)
                .font(.title3)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(UIStrings.aboutTagline)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            row(UIStrings.aboutAuthor, UIStrings.aboutAuthorName)
            Divider()
            row(UIStrings.aboutSystem, info.systemLine)
            Divider()
            HStack {
                Text(copied ? UIStrings.diagnosticsCopied : UIStrings.copyDiagnosticsHint)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(UIStrings.copyDiagnostics) { copyDiagnostics() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(UIStrings.aboutPrivacyTitle).font(.headline)
                Text(UIStrings.aboutPrivacyBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .accessibilityElement(children: .combine)
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(UIStrings.aboutCreditsTitle).font(.headline)
            Text(UIStrings.aboutCreditsBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.diagnostics, forType: .string)
        copied = true
    }
}
