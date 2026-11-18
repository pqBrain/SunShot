import AppKit
import Carbon.HIToolbox
import SunshotCore
import SunshotPlatform
import SwiftUI
import os

/// The global shortcuts (S10 Capture Area; S17 Capture Window and Open Studio), registered with the Carbon hot-key
/// API, which needs no Accessibility permission and works in the sandbox. The keys come from Settings; registration
/// is redone whenever they change, and paused while new keys are being recorded.
@MainActor
@Observable
final class GlobalCaptureHotkey {
    private static let logger = Logger(subsystem: "app.sunshot", category: "hotkey")
    private static let signature = OSType(0x534E_5348)  // "SNSH"

    /// Actions whose keys macOS refused (usually another app registered them first).
    private(set) var unavailable: Set<GlobalShortcutAction> = []
    /// True while Settings records new keys, so pressing the current ones doesn't run them.
    var isPaused = false {
        didSet { apply() }
    }

    @ObservationIgnored private var hotKeys: [GlobalShortcutAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var registered: [GlobalShortcutAction: GlobalShortcut] = [:]
    @ObservationIgnored private var wanted: [GlobalShortcutAction: GlobalShortcut] = [:]
    @ObservationIgnored private var perform: (@MainActor (GlobalShortcutAction) -> Void)?

    func isUnavailable(_ action: GlobalShortcutAction) -> Bool { unavailable.contains(action) }

    /// Registers `shortcuts` (an action left out is unregistered); a press runs `perform` with its action.
    func configure(
        _ shortcuts: [GlobalShortcutAction: GlobalShortcut],
        perform: @escaping @MainActor (GlobalShortcutAction) -> Void
    ) {
        self.perform = perform
        wanted = shortcuts
        apply()
    }

    private func apply() {
        let target = isPaused ? [:] : wanted
        guard target != registered || (!isPaused && !unavailable.isEmpty) else { return }
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        hotKeys = [:]
        registered = [:]
        var refused: Set<GlobalShortcutAction> = []
        if !target.isEmpty { installHandler() }
        for (index, action) in GlobalShortcutAction.allCases.enumerated() {
            guard let keys = target[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                keys.keyCode, Self.carbonModifiers(keys.modifiers), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys[action] = ref
                registered[action] = keys
            } else {
                Self.logger.error("could not register \(keys.description, privacy: .public): \(status)")
                refused.insert(action)
            }
        }
        // While paused nothing is registered on purpose; keep the last verdict for the shortcuts being edited.
        if !isPaused { unavailable = refused }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else { return noErr }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                let actions = GlobalShortcutAction.allCases
                guard status == noErr, id.signature == GlobalCaptureHotkey.signature, id.id >= 1,
                    Int(id.id) <= actions.count
                else { return noErr }
                let action = actions[Int(id.id) - 1]
                let hotkey = Unmanaged<GlobalCaptureHotkey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.perform?(action) }
                return noErr
            }, 1, &eventType, context, &handler)
    }

    private static func carbonModifiers(_ modifiers: GlobalShortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }
}

/// A short "copied" bubble near the bottom of the screen under the pointer; it never takes focus.
@MainActor
enum CaptureToast {
    private static var panel: NSPanel?

    static func show(_ message: String) {
        panel?.orderOut(nil)
        guard let screen = ScreenDisplays.screenUnderPointer else { return }
        let host = NSHostingView(
            rootView: Text(message)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .fixedSize())
        let size = host.fittingSize
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 80, width: size.width,
            height: size.height)
        let toast = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.level = .statusBar
        toast.backgroundColor = .clear
        toast.isOpaque = false
        toast.hasShadow = false
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        toast.contentView = host
        toast.orderFrontRegardless()
        NSAccessibility.post(
            element: toast, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        panel = toast
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard panel === toast else { return }
            toast.orderOut(nil)
            panel = nil
        }
    }
}
