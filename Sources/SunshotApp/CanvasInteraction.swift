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
    @FocusState private var isFocused: Bool
    /// S16: where the picked screenshot is being dragged to (view points), while reordering.
    @State private var reorderPoint: CGPoint?

    private enum Press { case move, tilt, padding, corner, reorder }

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
            if let target = reorderTargetOutline {
                OutlineShape(points: target)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                    .allowsHitTesting(false)
            }
            if let outline = model.pickedScreenshotOutline(viewWidth: size.width, viewHeight: size.height) {
                PickedScreenshotChrome(
                    outline: outline, offset: reorderOffset, delete: { model.deletePickedScreenshot() })
            }
        }
        .frame(width: size.width, height: size.height)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            guard !press.modifiers.contains(.command), model.selectedScreenshot != nil else { return .ignored }
            switch press.key {
            case .delete, .deleteForward: return model.deletePickedScreenshot() ? .handled : .ignored
            case .escape:
                model.clearScreenshotPick()
                return .handled
            default: return .ignored
            }
        }
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

    private var reorderTargetOutline: [LayoutPoint]? {
        guard let point = reorderPoint,
            let target = model.reorderTarget(x: point.x, y: point.y, viewWidth: size.width, viewHeight: size.height)
        else { return nil }
        return model.screenshotOutline(number: target, viewWidth: size.width, viewHeight: size.height)
    }

    /// How far the picked screenshot's chrome follows the pointer while it is being dragged.
    private var reorderOffset: CGSize {
        guard let point = reorderPoint, let start = reorderStart else { return .zero }
        return CGSize(width: point.x - start.x, height: point.y - start.y)
    }

    @State private var reorderStart: CGPoint?

    /// The picked screenshot's move handle (its top-left corner), when `point` is on it.
    private func handleCentre(near point: CGPoint) -> CGPoint? {
        guard let outline = model.pickedScreenshotOutline(viewWidth: size.width, viewHeight: size.height),
            let corner = outline.first
        else { return nil }
        return hypot(point.x - corner.x, point.y - corner.y) <= 16 ? CGPoint(x: corner.x, y: corner.y) : nil
    }

    private func finishReorder(at location: CGPoint) {
        model.dropPickedScreenshot(x: location.x, y: location.y, viewWidth: size.width, viewHeight: size.height)
        reorderPoint = nil
        reorderStart = nil
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
                    isFocused = true
                    model.pickScreenshot(
                        x: value.startLocation.x, y: value.startLocation.y, viewWidth: size.width,
                        viewHeight: size.height)
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
        // S16: with a screenshot picked, dragging it reorders; a drag anywhere else moves the whole layout.
        if handleCentre(near: point) != nil { return .reorder }
        if let picked = model.selectedScreenshot,
            model.screenshotNumber(x: point.x, y: point.y, viewWidth: size.width, viewHeight: size.height) == picked
        {
            return .reorder
        }
        if isOnHandle(point) { return .corner }
        guard region(at: point) == .content else { return .padding }
        return NSEvent.modifierFlags.contains(.shift) ? .tilt : .move
    }

    private func begin(_ press: Press, at start: CGPoint) {
        switch press {
        case .reorder:
            // The screenshot under the pointer at release is the one it swaps with.
            reorderStart = start
            reorderPoint = start
        case .move:
            model.clearScreenshotPick()
            model.beginPositionDrag(surfaceWidth: size.width, surfaceHeight: size.height)
        case .tilt: model.beginTiltDrag()
        case .corner: model.beginCornerDrag()
        case .padding:
            model.beginPaddingDrag(x: start.x, y: start.y, viewWidth: size.width, viewHeight: size.height)
        }
    }

    private func update(_ press: Press, translation: CGSize) {
        let (dx, dy) = (translation.width, translation.height)
        switch press {
        case .reorder:
            if let start = reorderStart {
                reorderPoint = CGPoint(x: start.x + dx, y: start.y + dy)
            }
        case .move: model.updatePositionDrag(translationX: dx, translationY: dy, modifiers: Self.modifiers)
        case .tilt: model.updateTiltDrag(translationX: dx, translationY: dy)
        case .corner:
            model.updateCornerDrag(translationX: dx, translationY: dy, viewWidth: size.width, viewHeight: size.height)
        case .padding: model.updatePaddingDrag(translationX: dx, translationY: dy)
        }
    }

    private func end(_ press: Press) {
        switch press {
        case .reorder: finishReorder(at: reorderPoint ?? .zero)
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

/// A closed outline through view points.
private struct OutlineShape: Shape {
    let points: [LayoutPoint]

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
    }
}

/// S16: outline of the screenshot picked in a screenshot layout, with two buttons: × deletes it (as Delete does)
/// and the move handle drags it onto another screenshot to swap their places (as dragging the screenshot does).
private struct PickedScreenshotChrome: View {
    let outline: [LayoutPoint]
    let offset: CGSize
    let delete: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            OutlineShape(points: outline)
                .stroke(Color.accentColor, lineWidth: 2.5)
                .offset(offset)
                .allowsHitTesting(false)
            if outline.count == 4 {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .glassEffect(.regular, in: .circle)
                    .allowsHitTesting(false)
                    .help(UIStrings.reorderPickedScreenshot)
                    .accessibilityLabel(UIStrings.reorderPickedScreenshot)
                    .position(x: outline[0].x + offset.width, y: outline[0].y + offset.height)
                Button(action: delete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help(UIStrings.deletePickedScreenshot)
                .accessibilityLabel(UIStrings.deletePickedScreenshot)
                .position(x: outline[1].x + offset.width, y: outline[1].y + offset.height)
            }
        }
    }
}
