import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// The S10 sheets on the editor window: crop, website capture, window picker, and the Screen Recording help.
struct CaptureSheets: ViewModifier {
    @Bindable var model: EditorModel

    func body(content: Content) -> some View {
        @Bindable var crop = model.crop
        @Bindable var capture = model.capture
        content
            .sheet(isPresented: $crop.isPresented) { CropDialog(model: model) }
            .sheet(isPresented: $capture.showsWebsiteSheet, onDismiss: { model.cancelWebsiteCapture() }) {
                WebsiteCaptureSheet(model: model)
            }
            .sheet(isPresented: $capture.showsWindowPicker) { WindowPickerSheet(model: model) }
            .alert(ScreenCaptureError.permissionDenied.title, isPresented: $capture.showsPermissionHelp) {
                Button(UIStrings.openPrivacySettings) {
                    if let url = ScreenDisplays.privacySettingsURL { NSWorkspace.shared.open(url) }
                }
                Button(UIStrings.cancel, role: .cancel) {}
            } message: {
                Text(ScreenCaptureError.permissionDenied.reason)
            }
    }
}

/// File ▸ Capture Website…: address, viewport, full page and delay; Cancel stops a running capture.
struct WebsiteCaptureSheet: View {
    @Bindable var model: EditorModel

    var body: some View {
        @Bindable var capture = model.capture
        Form {
            TextField(UIStrings.websiteAddress, text: $capture.websiteText, prompt: Text(UIStrings.websitePlaceholder))
                .textContentType(.URL)
                .onSubmit { if capture.canCaptureWebsite { model.captureWebsite() } }
                .accessibilityLabel(UIStrings.websiteAddress)
            Picker(UIStrings.captureViewport, selection: $capture.webOptions.viewport) {
                ForEach(WebViewport.allCases, id: \.self) { Text(UIStrings.viewportName($0)).tag($0) }
            }
            Toggle(UIStrings.captureFullPage, isOn: $capture.webOptions.fullPage)
                .help(UIStrings.captureFullPageHint)
            LabeledContent(UIStrings.captureDelay) {
                Stepper(
                    UIStrings.delayLabel(capture.webOptions.delaySeconds), value: $capture.webOptions.delaySeconds,
                    in: 0...WebCaptureOptions.maxDelaySeconds, step: 1)
            }
            if let error = capture.websiteError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
            }
        }
        .formStyle(.grouped)
        .disabled(capture.isCapturingWebsite)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if capture.isCapturingWebsite {
                    ProgressView().controlSize(.small)
                    Text(UIStrings.capturingWebsite).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                }
                Spacer()
                Button(UIStrings.cancel, role: .cancel) {
                    model.cancelWebsiteCapture()
                    capture.showsWebsiteSheet = false
                }
                .keyboardShortcut(.cancelAction)
                Button(UIStrings.captureButton) { model.captureWebsite() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!capture.canCaptureWebsite)
            }
            .padding(16)
        }
        .navigationTitle(UIStrings.websiteTitle)
        .frame(width: 460)
    }
}

/// File ▸ Capture Window…: the open windows of other apps; double-click or Capture.
struct WindowPickerSheet: View {
    @Bindable var model: EditorModel
    @State private var selection: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.windowPickerTitle).font(.headline)
            if model.capture.windows.isEmpty {
                Text(UIStrings.windowPickerEmpty).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            List(model.capture.windows, selection: $selection) { window in
                Text(UIStrings.windowLabel(window))
                    .lineLimit(1)
                    .tag(window.id)
                    .accessibilityLabel(UIStrings.windowLabel(window))
            }
            .contextMenu(forSelectionType: UInt32.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first { capture(id) }
            }
            .frame(height: 280)
            HStack {
                Spacer()
                Button(UIStrings.cancel, role: .cancel) { model.capture.showsWindowPicker = false }
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.captureButton) { if let selection { capture(selection) } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func capture(_ id: UInt32) {
        Task { await model.captureWindow(id: id) }
    }
}

/// The Capture menu on the toolbar (area, window, website).
struct CaptureToolbarMenu: View {
    let model: EditorModel

    var body: some View {
        Menu {
            Button(UIStrings.captureArea) { AreaCapture.start(model: model) }
            Button(UIStrings.captureWindow) { Task { await model.loadCapturableWindows() } }
            Button(UIStrings.captureWebsite) { model.capture.showsWebsiteSheet = true }
        } label: {
            Label(UIStrings.captureMenu, systemImage: "camera.viewfinder")
        }
        .help(UIStrings.captureAccessibility)
        .accessibilityLabel(UIStrings.captureAccessibility)
    }
}
