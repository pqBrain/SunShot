import AppKit
import Carbon.HIToolbox
import SunshotCore
import SunshotPlatform
import SwiftUI

/// File ▸ Capture Area…: a dimmed, borderless panel over the screen under the pointer; drag out an area, Esc
/// cancels. The panel closes before the capture, and Sunshot's own windows are excluded from it anyway.
@MainActor
enum AreaCapture {
    private static var panel: NSPanel?

    static func start(model: EditorModel) {
        guard panel == nil, model.ensureScreenCapturePermission() else {
            NSApp.activate()
            return
        }
        guard let screen = ScreenDisplays.screenUnderPointer, let displayID = ScreenDisplays.displayID(of: screen)
        else { return }
        let overlay = KeyPanel(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = NSHostingView(
            rootView: AreaSelectionView(size: screen.frame.size) { rect in
                finish(rect, displayID: displayID, model: model)
            })
        overlay.setFrame(screen.frame, display: true)
        panel = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    private static func finish(_ rect: LayoutRect?, displayID: UInt32, model: EditorModel) {
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
        guard let rect, AreaSelection.isCapturable(rect) else { return }
        Task {
            // Let the window server remove the overlay before the screen is read.
            try? await Task.sleep(for: .milliseconds(150))
            await model.captureArea(rect, displayID: displayID)
            NSApp.activate()
        }
    }
}

/// Borderless panels don't become key by default; this one must, to receive Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct AreaSelectionView: View {
    let size: CGSize
    let finish: (LayoutRect?) -> Void
    @State private var selection: LayoutRect?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if let selection { path.addRect(Self.cgRect(selection)) }
            }
            .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
            if let selection {
                Rectangle()
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.x, y: selection.y)
                Text(UIStrings.pixelSize(width: Int(selection.width), height: Int(selection.height)))
                    .font(.caption.monospacedDigit())
                    .padding(4)
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .offset(x: selection.x, y: max(0, selection.y - 24))
            } else {
                Text(UIStrings.captureAreaHint)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    selection = AreaSelection.rect(
                        from: (value.startLocation.x, value.startLocation.y), to: (value.location.x, value.location.y),
                        displayWidth: size.width, displayHeight: size.height)
                }
                .onEnded { _ in finish(selection) }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            finish(nil)
            return .handled
        }
    }

    private static func cgRect(_ rect: LayoutRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

/// The optional global ⌥⇧⌘4 shortcut (Settings ▸ Capture Area from anywhere; off by default), registered with
/// the Carbon hot-key API, which needs no Accessibility permission and works in the sandbox.
@MainActor
final class GlobalCaptureHotkey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func setEnabled(_ enabled: Bool, action: @escaping @MainActor () -> Void) {
        self.action = action
        if enabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
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
        let modifiers = UInt32(cmdKey | optionKey | shiftKey)
        let id = EventHotKeyID(signature: OSType(0x534E_5348), id: 1)  // "SNSH"
        RegisterEventHotKey(UInt32(kVK_ANSI_4), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
