import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Sunshot ▸ Settings… (⌘,). Values are written to UserDefaults as they change.
struct SettingsView: View {
    @Bindable var controller: DocumentController

    var body: some View {
        Form {
            Picker(UIStrings.appearance, selection: $controller.settings.appearance) {
                ForEach(AppearanceSetting.allCases, id: \.self) { Text(UIStrings.appearanceName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(UIStrings.appearance)

            FilenameFormatField(controller: controller)

            LabeledContent(UIStrings.exportFolder) {
                HStack {
                    Text(controller.settings.exportFolder?.path ?? UIStrings.exportFolderNone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .accessibilityLabel(
                            "\(UIStrings.exportFolder): \(controller.settings.exportFolder?.path ?? UIStrings.exportFolderNone)"
                        )
                    Spacer()
                    Button(UIStrings.choose) { chooseFolder() }
                        .accessibilityLabel("\(UIStrings.choose) \(UIStrings.exportFolder)")
                    Button(UIStrings.clear) { controller.settings.exportFolder = nil }
                        .disabled(controller.settings.exportFolder == nil)
                        .accessibilityLabel("\(UIStrings.clear) \(UIStrings.exportFolder)")
                }
            }

            Toggle(UIStrings.confirmReset, isOn: $controller.settings.confirmReset)

            Toggle(isOn: $controller.settings.captureHotkeyEnabled) {
                Text(UIStrings.globalCaptureShortcut)
                Text(UIStrings.globalCaptureShortcutHint)
            }

            Picker(UIStrings.defaultTemplate, selection: $controller.defaultTemplateID) {
                ForEach(controller.model.templates.templates) { Text($0.name).tag($0.id) }
            }
            .disabled(controller.model.templates.templates.isEmpty)

            Toggle(UIStrings.suggestDeviceSetting, isOn: $controller.settings.suggestDevice)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(UIStrings.settingsTitle)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = controller.settings.exportFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.settings.exportFolder = url
    }
}

/// Template field with a live preview of the resulting file name and a Reset button.
struct FilenameFormatField: View {
    @Bindable var controller: DocumentController

    var body: some View {
        let preview = FilenamePreview.preview(template: controller.settings.filenameTemplate, date: Date())
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(UIStrings.filenameFormat, text: $controller.settings.filenameTemplate)
                    .accessibilityLabel(UIStrings.filenameFormat)
                Button(UIStrings.reset) { controller.settings.filenameTemplate = SunshotDefaults.filenameTemplate }
                    .accessibilityLabel(UIStrings.resetSection(UIStrings.filenameFormat))
            }
            Text(preview.name)
                .font(.callout.monospaced())
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .textSelection(.enabled)
            if let warning = preview.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
            }
            Text(UIStrings.filenameTokensHint)
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
        }
    }
}
