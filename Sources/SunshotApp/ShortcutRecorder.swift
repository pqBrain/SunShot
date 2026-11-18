import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Settings controls for the global shortcuts (S10 Capture Area; S17 Capture Window, Open Studio): for each, on/off
/// and the keys (click, then press new ones); then what a shortcut capture does.
struct GlobalCaptureSettings: View {
    @Bindable var controller: DocumentController
    let hotkey: GlobalCaptureHotkey

    var body: some View {
        ForEach(GlobalShortcutAction.allCases, id: \.self) { action in
            GlobalShortcutRow(controller: controller, hotkey: hotkey, action: action)
        }

        Picker(UIStrings.afterShortcutCapture, selection: $controller.settings.globalCaptureDestination) {
            ForEach(GlobalCaptureDestination.allCases, id: \.self) {
                Text(UIStrings.captureDestinationName($0)).tag($0)
            }
        }
        .disabled(!controller.settings.hasCaptureShortcut)
    }
}

/// One global shortcut: on/off, the recorder with Restore Default, and why its keys don't work (if they don't).
private struct GlobalShortcutRow: View {
    @Bindable var controller: DocumentController
    let hotkey: GlobalCaptureHotkey
    let action: GlobalShortcutAction

    var body: some View {
        let settings = controller.settings
        let enabled = settings.isShortcutEnabled(action)
        Toggle(isOn: enabledBinding) {
            Text(UIStrings.globalShortcutTitle(action))
            Text(UIStrings.globalShortcutHint(action, settings.shortcut(for: action)))
        }

        LabeledContent(UIStrings.captureShortcutLabel) {
            HStack {
                ShortcutRecorder(
                    shortcut: keysBinding, hotkey: hotkey, name: UIStrings.globalShortcutName(action),
                    conflict: { controller.settings.shortcutConflict($0, for: action) })
                Button(UIStrings.restoreDefaultShortcut) { restoreDefault() }
                    .disabled(settings.shortcut(for: action) == action.defaultShortcut)
                    .accessibilityLabel("\(UIStrings.restoreDefaultShortcut) \(UIStrings.globalShortcutName(action))")
            }
        }
        .disabled(!enabled)

        if enabled, let other = settings.shortcutConflict(settings.shortcut(for: action), for: action),
            settings.activeShortcuts[action] == nil
        {
            Text(UIStrings.shortcutInUse(by: other)).font(.callout).foregroundStyle(.red)
        } else if enabled && hotkey.isUnavailable(action) {
            Text(UIStrings.shortcutUnavailable).font(.callout).foregroundStyle(.red)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.isShortcutEnabled(action) },
            set: { controller.settings.setShortcutEnabled($0, for: action) })
    }

    private var keysBinding: Binding<GlobalShortcut> {
        Binding(
            get: { controller.settings.shortcut(for: action) },
            set: { controller.settings.setShortcut($0, for: action) })
    }

    /// The default keys, unless another shortcut took them (then the recorder is the way to choose).
    private func restoreDefault() {
        guard controller.settings.shortcutConflict(action.defaultShortcut, for: action) == nil else { return }
        controller.settings.setShortcut(action.defaultShortcut, for: action)
    }
}

/// A button that shows the shortcut; clicked, it records the next key press with modifiers. Esc cancels; keys
/// that can't be a global shortcut are refused with the reason.
struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut
    let hotkey: GlobalCaptureHotkey
    /// The action's name, for VoiceOver.
    let name: String
    /// S17: the other global shortcut already using these keys, if any.
    let conflict: (GlobalShortcut) -> GlobalShortcutAction?
    @State private var isRecording = false
    @State private var problem: String?
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
            .accessibilityLabel("\(name) \(UIStrings.captureShortcutLabel): \(shortcut.description)")
            .accessibilityHint(UIStrings.recordShortcutHelp)
            if let problem {
                Text(problem)
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
            problem = UIStrings.shortcutProblem(reason)
            return
        }
        if let other = conflict(candidate) {
            problem = UIStrings.shortcutInUse(by: other)
            return
        }
        problem = nil
        shortcut = candidate
        stop()
    }
}
