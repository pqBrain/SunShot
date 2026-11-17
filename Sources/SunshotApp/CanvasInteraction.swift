import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// S6: direct manipulation on the main preview.
/// - Screenshot: drag to move (Position-pad snapping, ⌥ free, ⌘ no snap), ⇧-drag to tilt, double-click to crop.
/// - Backdrop: drag outward / inward for padding. Drop an image there to use it as the background.
/// - Corner handle: drag for the corner radius. Pinch zooms, twist rotates (⌘: no 45° snap) anywhere on the canvas.
/// - Click reveals the matching inspector section; right-click offers quick actions.
/// Draws only chrome (guides, handle); the document pixels come from the shared renderer.
struct CanvasInteractionLayer: View {
    let model: EditorModel
    let size: CGSize
    @State private var press: Press?
    @State private var dragging = false
    @State private var hoverRegion: CanvasRegion?
    @State private var hoversHandle = false

    private enum Press { case move, tilt, padding, corner }

    /// Movement (points) before a press becomes a drag instead of a click.
    private static let clickSlop: CGFloat = 3
    private static let handleRadius: CGFloat = 7

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(.rect)
            GuideLines(guides: model.layout.guides, size: size)
            if let handle = visibleHandle {
                Circle()
                    .fill(.white)
                    .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
                    .frame(width: Self.handleRadius * 2, height: Self.handleRadius * 2)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .position(handle)
                    .allowsHitTesting(false)
                    .accessibilityLabel(UIStrings.cornerHandle)
            }
        }
        .frame(width: size.width, height: size.height)
        .gesture(dragGesture)
        .simultaneousGesture(pinchGesture)
        .simultaneousGesture(twistGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverRegion = region(at: location)
                hoversHandle = isOnHandle(location)
            case .ended:
                hoverRegion = nil
                hoversHandle = false
            }
        }
        .pointerStyle(pointer)
        .dropDestination(for: URL.self) { urls, location in
            Task { await model.importDropped(urls, on: region(at: location)) }
            return true
        }
        .contextMenu { contextMenu }
        .help(UIStrings.canvasGestureHint)
    }

    // MARK: Chrome

    private var handlePoint: CGPoint? {
        model.cornerHandlePoint(viewWidth: size.width, viewHeight: size.height).map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// The handle shows while hovering the screenshot or dragging it.
    private var visibleHandle: CGPoint? {
        guard hoverRegion == .content || press == .corner, press != .move, press != .tilt else { return nil }
        return handlePoint
    }

    private func isOnHandle(_ point: CGPoint) -> Bool {
        guard let handle = handlePoint else { return false }
        return hypot(point.x - handle.x, point.y - handle.y) <= Self.handleRadius + 4
    }

    private var pointer: PointerStyle? {
        if press == .corner || hoversHandle { return .frameResize(position: .topLeading) }
        if press == .move, dragging { return .grabActive }
        return hoverRegion == .content ? .grabIdle : nil
    }

    private func region(at point: CGPoint) -> CanvasRegion {
        model.canvasRegion(x: point.x, y: point.y, viewWidth: size.width, viewHeight: size.height) ?? .backdrop
    }

    @ViewBuilder private var contextMenu: some View {
        Button(UIStrings.canvasShuffleBackdrop) { model.perform { $0.shuffleAutoBackgrounds() } }
        Button(UIStrings.canvasNoBackdrop) { model.perform { $0.setBackdropKind(.none) } }
        Divider()
        Button(UIStrings.canvasResetPosition) { model.perform { $0.resetPosition() } }
            .disabled(model.session.contentTransform.isIdentity)
        Button(UIStrings.canvasCrop) { model.openCrop() }.disabled(!model.canCrop)
        Button(UIStrings.canvasCopyPNG) { Task { await model.copyPNG(to: .general) } }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if press == nil { press = startPress(at: value.startLocation) }
                guard let press else { return }
                if !dragging {
                    guard hypot(value.translation.width, value.translation.height) >= Self.clickSlop else { return }
                    dragging = true
                    begin(press, at: value.startLocation)
                }
                update(press, translation: value.translation)
            }
            .onEnded { value in
                if dragging, let press {
                    end(press)
                } else if press != nil {
                    let region = region(at: value.startLocation)
                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                        model.canvasDoubleClicked(region)
                    } else {
                        model.canvasClicked(region)
                    }
                }
                dragging = false
                press = nil
            }
    }

    private func startPress(at point: CGPoint) -> Press {
        if isOnHandle(point) { return .corner }
        guard region(at: point) == .content else { return .padding }
        return NSEvent.modifierFlags.contains(.shift) ? .tilt : .move
    }

    private func begin(_ press: Press, at start: CGPoint) {
        switch press {
        case .move: model.beginPositionDrag(surfaceWidth: size.width, surfaceHeight: size.height)
        case .tilt: model.beginTiltDrag()
        case .corner: model.beginCornerDrag()
        case .padding:
            model.beginPaddingDrag(x: start.x, y: start.y, viewWidth: size.width, viewHeight: size.height)
        }
    }

    private func update(_ press: Press, translation: CGSize) {
        let (dx, dy) = (translation.width, translation.height)
        switch press {
        case .move: model.updatePositionDrag(translationX: dx, translationY: dy, modifiers: Self.modifiers)
        case .tilt: model.updateTiltDrag(translationX: dx, translationY: dy)
        case .corner:
            model.updateCornerDrag(translationX: dx, translationY: dy, viewWidth: size.width, viewHeight: size.height)
        case .padding: model.updatePaddingDrag(translationX: dx, translationY: dy)
        }
    }

    private func end(_ press: Press) {
        switch press {
        case .move: model.endPositionDrag()
        case .tilt: model.endTiltDrag()
        case .corner: model.endCornerDrag()
        case .padding: model.endPaddingDrag()
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                model.beginPinch()
                model.updatePinch(magnification: value.magnification)
            }
            .onEnded { _ in model.endPinch() }
    }

    private var twistGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                model.beginTwist()
                model.updateTwist(degrees: value.rotation.degrees, snaps: !NSEvent.modifierFlags.contains(.command))
            }
            .onEnded { _ in model.endTwist() }
    }

    private static var modifiers: DragModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: DragModifiers = []
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
