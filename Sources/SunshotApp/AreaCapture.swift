import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// File ▸ Capture Area…: a dimmed, borderless panel over the screen under the pointer; drag out an area, Esc
/// cancels, Space switches to picking a window (S16). The panel closes before the capture, and Sunshot's own windows
/// are excluded from it anyway.
@MainActor
enum AreaCapture {
    private static var panel: NSPanel?
    /// True from the shortcut until the overlay is up (the screen is being frozen), so a second press is ignored.
    private static var freezing = false

    /// `destination` is where the capture goes: the studio for File ▸ Capture Area…, the shortcut's choice (S16:
    /// copied with the default style unless changed) for the global shortcut and the menu bar.
    static func start(controller: DocumentController, destination: GlobalCaptureDestination = .editor) {
        guard panel == nil, !freezing, !WindowCapture.isActive, controller.model.ensureScreenCapturePermission() else {
            NSApp.activate()
            return
        }
        guard let screen = ScreenDisplays.screenUnderPointer, let displayID = ScreenDisplays.displayID(of: screen)
        else { return }
        let size = screen.frame.size
        freezing = true
        Task {
            defer { freezing = false }
            // Freeze first: the picture is taken the moment the shortcut fires, before any overlay is drawn.
            guard
                let frozen = await controller.model.freezeDisplay(
                    size: (size.width, size.height), displayID: displayID)
            else {
                return
            }
            let overlay = CapturePanel.make(frame: screen.frame)
            overlay.contentView = NSHostingView(
                rootView: FreezeOverlayView(frozen: frozen, size: size) { outcome, rect, marks in
                    finish(
                        outcome, rect, marks: marks, frozen: frozen, size: size, controller: controller,
                        destination: destination)
                } switchToWindow: {
                    close()
                    WindowCapture.start(controller: controller, destination: destination)
                })
            overlay.setFrame(screen.frame, display: true)
            panel = overlay
            overlay.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }

    static var isActive: Bool { panel != nil || freezing }

    private static func close() {
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
    }

    private static func finish(
        _ outcome: FreezeOutcome, _ rect: LayoutRect?, marks: [Annotation], frozen: CGImage, size: CGSize,
        controller: DocumentController,
        destination: GlobalCaptureDestination
    ) {
        close()
        guard outcome != .cancel, let rect, AreaSelection.isCapturable(rect) else { return }
        // ⌘C always copies with the default style applied, whatever "After a shortcut capture" says (that setting
        // only decides what a plain drag does elsewhere); Studio always opens the studio.
        let destination: GlobalCaptureDestination = outcome == .studio ? .editor : .styledClipboard
        Task {
            let copied = await controller.deliverFrozen(
                frozen, displaySize: (size.width, size.height), crop: rect, marks: marks, to: destination)
            CaptureDelivery.show(copied: copied, destination: destination, controller: controller)
        }
    }
}

/// S16: hands a finished selection to the controller after the overlay has gone, then shows the result: the
/// "copied" bubble for clipboard captures (Sunshot stays in the background), the studio for editor captures.
@MainActor
enum CaptureDelivery {
    static func deliver(_ source: CaptureSource, controller: DocumentController, destination: GlobalCaptureDestination)
    {
        Task {
            // Let the window server remove the overlay before the screen is read.
            try? await Task.sleep(for: .milliseconds(150))
            let copied = await controller.deliverCapture(source, to: destination)
            show(copied: copied, destination: destination, controller: controller)
        }
    }

    static func show(copied: Bool, destination: GlobalCaptureDestination, controller: DocumentController) {
        if destination.copies {
            // Only a failure brings Sunshot forward to explain it.
            if copied { CaptureToast.show(UIStrings.copiedToClipboard) } else { Studio.show(controller) }
        } else {
            Studio.show(controller)
        }
    }
}

/// The borderless, all-spaces panel both capture overlays use.
@MainActor
enum CapturePanel {
    static func make(frame: NSRect) -> NSPanel {
        let overlay = KeyPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.level = .screenSaver
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return overlay
    }
}

/// Borderless panels don't become key by default; this one must, to receive Esc.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
