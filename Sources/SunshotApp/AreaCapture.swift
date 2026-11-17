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

    /// `destination` is where the capture goes: the studio for File ▸ Capture Area…, the shortcut's choice (S16:
    /// copied with the default style unless changed) for the global shortcut and the menu bar.
    static func start(controller: DocumentController, destination: GlobalCaptureDestination = .editor) {
        guard panel == nil, !WindowCapture.isActive, controller.model.ensureScreenCapturePermission() else {
            NSApp.activate()
            return
        }
        guard let screen = ScreenDisplays.screenUnderPointer, let displayID = ScreenDisplays.displayID(of: screen)
        else { return }
        let overlay = CapturePanel.make(frame: screen.frame)
        overlay.contentView = NSHostingView(
            rootView: AreaSelectionView(size: screen.frame.size) { rect in
                finish(rect, displayID: displayID, controller: controller, destination: destination)
            } switchToWindow: {
                close()
                WindowCapture.start(controller: controller, destination: destination)
            })
        overlay.setFrame(screen.frame, display: true)
        panel = overlay
        overlay.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    static var isActive: Bool { panel != nil }

    private static func close() {
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
    }

    private static func finish(
        _ rect: LayoutRect?, displayID: UInt32, controller: DocumentController, destination: GlobalCaptureDestination
    ) {
        close()
        guard let rect, AreaSelection.isCapturable(rect) else { return }
        CaptureDelivery.deliver(.area(rect, displayID: displayID), controller: controller, destination: destination)
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
            if destination.copies {
                // Only a failure brings Sunshot forward to explain it.
                if copied { CaptureToast.show(UIStrings.copiedToClipboard) } else { Studio.show(controller) }
            } else {
                Studio.show(controller)
            }
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

private struct AreaSelectionView: View {
    let size: CGSize
    let finish: (LayoutRect?) -> Void
    let switchToWindow: () -> Void
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
                Text(UIStrings.areaSwitchHint)
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
        .onKeyPress(.space) {
            guard selection == nil else { return .ignored }
            switchToWindow()
            return .handled
        }
    }

    private static func cgRect(_ rect: LayoutRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
