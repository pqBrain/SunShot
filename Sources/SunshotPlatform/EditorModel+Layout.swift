import CoreGraphics
public import SunshotCore
import SunshotRender

/// S6: position drag, keyboard nudges, typed zoom / rotation, layout presets (animated) and their thumbnails.
extension EditorModel {
    // MARK: Position drag

    /// Starts dragging the position handle on a mini canvas of `width` × `height` points.
    public func beginPositionDrag(surfaceWidth width: Double, surfaceHeight height: Double) {
        beginGesture()
        layout.drag = session.positionDrag(surfaceWidth: width, surfaceHeight: height)
    }

    /// Pointer moved `dx`, `dy` points from where the drag started.
    public func updatePositionDrag(translationX dx: Double, translationY dy: Double, modifiers: DragModifiers) {
        guard var drag = layout.drag else { return }
        let result = drag.update(translationX: dx, translationY: dy, modifiers: modifiers)
        layout.drag = drag
        layout.guides = result.guides
        perform { $0.moveContent(x: result.x, y: result.y) }
    }

    /// Ends the drag: one undo step "Move Content", guides cleared.
    public func endPositionDrag() {
        layout.drag = nil
        layout.guides = []
        endGesture(EditorSession.moveContentActionName)
    }

    /// Arrow keys on the handle: 0.01 per press (⇧: 0.05).
    public func nudgePosition(dx: Double, dy: Double, large: Bool) {
        let transform = session.contentTransform
        let x = PositionDrag.nudged(transform.x, by: dx, large: large)
        let y = PositionDrag.nudged(transform.y, by: dy, large: large)
        perform { $0.moveContent(x: x, y: y) }
    }

    /// Typed zoom percent. Returns false (value kept) for non-numeric text.
    @discardableResult
    public func setZoom(text: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setZoom(text: text) }
        return accepted
    }

    /// Typed rotation in degrees. Returns false (value kept) for non-numeric text.
    @discardableResult
    public func setRotation(text: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setRotation(text: text) }
        return accepted
    }

    // MARK: Layout presets

    public var selectedLayoutPreset: LayoutPreset? { layout.library.catalog?.preset(id: session.layoutPresetID) }

    /// Applies `preset` (one undo step) and animates the preview there over 300 ms ease-in-out, or instantly
    /// with Reduce Motion. The document holds the target at once, so exports never see an intermediate frame.
    @discardableResult
    public func applyLayoutPreset(_ preset: LayoutPreset) -> Task<Void, Never> {
        finishContinuousEdit()
        layout.animationTask?.cancel()
        let from = layout.animatingTransform ?? session.contentTransform
        session.applyLayoutPreset(preset)
        let target = session.contentTransform
        guard from != target, !layout.reduceMotion() else {
            layout.animatingTransform = nil
            layout.lastAnimation = nil
            return Task { await refreshPreview() }
        }
        let task = Task { await animatePreview(from: from, to: target) }
        layout.animationTask = task
        return task
    }

    private func animatePreview(from: ContentTransform, to target: ContentTransform) async {
        renderGeneration += 1
        let generation = renderGeneration
        let clock = ContinuousClock()
        let start = clock.now
        var frames: [ContentTransform] = []
        while !Task.isCancelled, generation == renderGeneration {
            let elapsed = clock.now - start
            guard elapsed < TransformAnimation.duration else { break }
            let frame = TransformAnimation.frame(from: from, to: target, elapsed: elapsed)
            layout.animatingTransform = frame
            frames.append(frame)
            var document = session.document
            document.project.placement.transform = frame
            let image = await renderPreviewImage(document)
            guard generation == renderGeneration, !Task.isCancelled else { break }
            preview = image
            // Cap at ~60 fps when frames render quickly.
            let next = start + .milliseconds(16) * frames.count
            if next > clock.now { try? await Task.sleep(until: next, clock: clock) }
        }
        let finished = generation == renderGeneration && !Task.isCancelled
        if finished {
            frames.append(target)
            layout.lastAnimation = (frames, clock.now - start)
        }
        // A cancelled animation was replaced by a newer one, which owns the in-flight transform now.
        if !Task.isCancelled { layout.animatingTransform = nil }
        // Ends exactly on the document (the target, unless a later edit superseded it).
        if finished { await refreshPreview() }
    }

    /// Renders `document` the way the preview does (same renderer, grid and scale).
    func renderPreviewImage(_ document: EditorDocument) async -> CGImage? {
        let grid = SunshotPalette.transparencyGrid(dark: isDarkAppearance)
        let scale = previewScale
        return try? await Task.detached(priority: .userInitiated) {
            try Renderer.render(document: document, scale: scale, showsTransparencyGrid: true, grid: grid)
        }.value
    }

    // MARK: Thumbnails

    /// Re-renders the preset thumbnails after the style or content changed (debounced, off the main actor).
    /// Changes of the placement alone don't invalidate them; recent sets are cached by (document, preset).
    func scheduleLayoutThumbnails() {
        let presets = layout.presets
        guard !presets.isEmpty,
            let key = LayoutThumbnailKey(document: session.document, maxSide: LayoutThumbnails.defaultMaxSide)
        else {
            layout.thumbnailTask?.cancel()
            layout.thumbnailTask = nil
            layout.pendingThumbnailKey = nil
            layout.thumbnailKey = nil
            layout.thumbnails = [:]
            return
        }
        guard key != layout.thumbnailKey, key != layout.pendingThumbnailKey else { return }
        layout.thumbnailTask?.cancel()
        if let cached = layout.cachedThumbnails(for: key) {
            layout.pendingThumbnailKey = nil
            layout.thumbnailKey = key
            layout.thumbnails = cached
            return
        }
        layout.pendingThumbnailKey = key
        let document = session.document
        let debounce = layout.thumbnailDebounce
        layout.thumbnailTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let images = try? await Task.detached(priority: .utility) {
                try LayoutThumbnails.render(document: document, presets: presets)
            }.value
            guard !Task.isCancelled, let self, self.layout.pendingThumbnailKey == key else { return }
            self.layout.pendingThumbnailKey = nil
            self.layout.thumbnailKey = key
            self.layout.thumbnails = images ?? [:]
            self.layout.storeThumbnails(images ?? [:], for: key)
        }
    }
}
