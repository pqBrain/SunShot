import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Settings controls for the global Capture Area shortcut: on/off, the keys (click, then press new ones), and
/// what a shortcut capture does.
struct GlobalCaptureSettings: View {
    @Bindable var controller: DocumentController
    let hotkey: GlobalCaptureHotkey

    var body: some View {
        Toggle(isOn: $controller.settings.captureHotkeyEnabled) {
            Text(UIStrings.globalCaptureShortcut)
            Text(UIStrings.globalCaptureShortcutHint(controller.settings.captureShortcut))
        }

        LabeledContent(UIStrings.captureShortcutLabel) {
            HStack {
                ShortcutRecorder(shortcut: $controller.settings.captureShortcut, hotkey: hotkey)
                Button(UIStrings.restoreDefaultShortcut) { controller.settings.captureShortcut = .default }
                    .disabled(controller.settings.captureShortcut == .default)
            }
        }
        .disabled(!controller.settings.captureHotkeyEnabled)

        if controller.settings.captureHotkeyEnabled && hotkey.isUnavailable {
            Text(UIStrings.shortcutUnavailable)
                .font(.callout)
                .foregroundStyle(.red)
        }

        Picker(UIStrings.afterShortcutCapture, selection: $controller.settings.globalCaptureDestination) {
            ForEach(GlobalCaptureDestination.allCases, id: \.self) {
                Text(UIStrings.captureDestinationName($0)).tag($0)
            }
        }
        .disabled(!controller.settings.captureHotkeyEnabled)
    }
}

/// A button that shows the shortcut; clicked, it records the next key press with modifiers. Esc cancels; keys
/// that can't be a global shortcut are refused with the reason.
struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut
    let hotkey: GlobalCaptureHotkey
    @State private var isRecording = false
    @State private var problem: GlobalShortcut.Problem?
    @State private var monitor: Any?
    /// Modifiers held while recording, shown live so the user sees their keys arrive.
    @State private var held: GlobalShortcut.Modifiers = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 96)
            }
            .help(UIStrings.recordShortcutHelp)
            .accessibilityLabel("\(UIStrings.captureShortcutLabel): \(shortcut.description)")
            .accessibilityHint(UIStrings.recordShortcutHelp)
            if let problem {
                Text(UIStrings.shortcutProblem(problem))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        guard isRecording else { return shortcut.description }
        guard !held.isEmpty else { return UIStrings.recordShortcutPrompt }
        return GlobalShortcut(keyCode: 0, modifiers: held, keyLabel: "").description
    }

    private func start() {
        problem = nil
        held = []
        isRecording = true
        hotkey.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                held = Self.modifiers(event.modifierFlags)
            } else {
                record(event)
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = []
        isRecording = false
        hotkey.isPaused = false
    }

    private static func modifiers(_ eventFlags: NSEvent.ModifierFlags) -> GlobalShortcut.Modifiers {
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    private func record(_ event: NSEvent) {
        let modifiers = Self.modifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            problem = nil
            stop()
            return
        }
        let keyCode = UInt32(event.keyCode)
        let candidate = GlobalShortcut(
            keyCode: keyCode, modifiers: modifiers,
            keyLabel: GlobalShortcut.label(keyCode: keyCode, characters: event.charactersIgnoringModifiers))
        if let reason = candidate.problem {
            problem = reason
            return
        }
        problem = nil
        shortcut = candidate
        stop()
    }
}
