import AppKit
import Carbon.HIToolbox
import SunshotCore
import SunshotPlatform
import SwiftUI
import os

/// The optional global Capture Area shortcut (Settings ▸ Capture Area from anywhere; off by default), registered
/// with the Carbon hot-key API, which needs no Accessibility permission and works in the sandbox. The keys come
/// from Settings; registration is redone whenever they change, and paused while new keys are being recorded.
@MainActor
@Observable
final class GlobalCaptureHotkey {
    private static let logger = Logger(subsystem: "app.sunshot", category: "hotkey")

    /// macOS refused the keys (usually another app registered them first).
    private(set) var isUnavailable = false
    /// True while Settings records new keys, so pressing the current ones doesn't start a capture.
    var isPaused = false {
        didSet { apply() }
    }

    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var registered: GlobalShortcut?
    @ObservationIgnored private var wanted: GlobalShortcut?
    @ObservationIgnored private var action: (@MainActor () -> Void)?

    /// Registers `shortcut` (nil unregisters) to run `action`.
    func configure(_ shortcut: GlobalShortcut?, action: @escaping @MainActor () -> Void) {
        self.action = action
        wanted = shortcut
        apply()
    }

    private func apply() {
        let target = isPaused ? nil : wanted
        guard target != registered || (target != nil && hotKey == nil) else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registered = nil
        guard let target else {
            if !isPaused { isUnavailable = false }
            return
        }
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x534E_5348), id: 1)  // "SNSH"
        let status = RegisterEventHotKey(
            target.keyCode, Self.carbonModifiers(target.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKey = ref
            registered = target
            isUnavailable = false
        } else {
            Self.logger.error("could not register \(target.description, privacy: .public): \(status)")
            isUnavailable = true
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let hotkey = Unmanaged<GlobalCaptureHotkey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.action?() }
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
