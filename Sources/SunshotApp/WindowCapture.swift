import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// S16: Capture Window the way the system screenshot does it: a clear panel over every screen; the window under
/// the pointer is tinted and outlined with its name and size, a click captures it, Space switches to an area and
/// Esc cancels. Hit-testing and coordinates live in `WindowPicking` (Core).
@MainActor
enum WindowCapture {
    private static var panels: [NSPanel] = []
    private static var eventMonitor: Any?
    private static var tracking: Task<Void, Never>?

    static var isActive: Bool { !panels.isEmpty }

    static func start(controller: DocumentController, destination: GlobalCaptureDestination = .editor) {
        guard !isActive, !AreaCapture.isActive else { return }
        Task {
            guard let windows = await controller.model.pickableWindows() else {
                NSApp.activate()
                return
            }
            open(windows: windows, controller: controller, destination: destination)
        }
    }

    private static func open(
        windows: [CapturableWindow], controller: DocumentController, destination: GlobalCaptureDestination
    ) {
        guard !isActive, let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let state = WindowHoverState(windows: windows)
        let pick: (CapturableWindow?) -> Void = { window in
            close()
            guard let window else { return }
            CaptureDelivery.deliver(.window(window.id), controller: controller, destination: destination)
        }
        for screen in NSScreen.screens {
            let frame = screen.frame
            let screenRect = WindowPicking.topLeftFrame(
                x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, mainHeight: mainHeight)
            let overlay = CapturePanel.make(frame: frame)
            overlay.contentView = NSHostingView(
                rootView: WindowHoverView(state: state, screen: screenRect))
            overlay.setFrame(frame, display: true)
            overlay.orderFrontRegardless()
            panels.append(overlay)
        }
        // The panel under the pointer takes the keys (Esc, Space); the others only draw. Clicks and keys are read
        // by one monitor, so a first click on any screen's panel picks without activating it first.
        let underPointer = panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels.first
        underPointer?.makeKey()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .leftMouseDown {
                pick(state.hovered)
                return nil
            }
            switch event.keyCode {
            case 53:  // Esc
                pick(nil)
                return nil
            case 49:  // Space: pick an area instead
                close()
                AreaCapture.start(controller: controller, destination: destination)
                return nil
            default:
                return event
            }
        }
        // The pointer is polled rather than tracked: hover tracking needs an active app, and Sunshot usually isn't.
        tracking = Task {
            while !Task.isCancelled {
                state.update(globalPointer: NSEvent.mouseLocation, mainHeight: mainHeight)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private static func close() {
        tracking?.cancel()
        tracking = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }
}

/// Which window the pointer is over, shared by the overlays of every screen.
@MainActor
@Observable
final class WindowHoverState {
    let windows: [CapturableWindow]
    private(set) var hovered: CapturableWindow?

    init(windows: [CapturableWindow]) {
        self.windows = windows
    }

    /// `point` in global top-left display points.
    func hover(at point: (x: Double, y: Double)) {
        let window = WindowPicking.window(at: point, in: windows)
        if window?.id != hovered?.id { hovered = window }
    }

    /// From AppKit's bottom-left global mouse location.
    func update(globalPointer location: NSPoint, mainHeight: Double) {
        hover(at: (location.x, mainHeight - location.y))
    }
}

private struct WindowHoverView: View {
    let state: WindowHoverState
    /// This screen's frame in global top-left display points.
    let screen: LayoutRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)  // keeps clicks off the windows below; the desktop stays visible
            if let window = state.hovered, let frame = window.frame {
                highlight(window, local: WindowPicking.local(frame, on: screen))
            } else {
                Text(UIStrings.windowPickHint)
                    .padding(12)
                    .glassEffect(.regular, in: .capsule)
                    .frame(width: screen.width, height: screen.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .onAppear { NSCursor.arrow.set() }
    }

    private func highlight(_ window: CapturableWindow, local rect: LayoutRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.22))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 3)
            VStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .medium))
                    .accessibilityHidden(true)
                Text(UIStrings.windowPickLabel(window))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(12)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.x, y: rect.y)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(UIStrings.windowPickLabel(window))
        .animation(.smooth(duration: 0.12), value: window.id)
    }
}
