public import CoreGraphics
public import Foundation
public import SunshotCore
public import SunshotRender

/// What the Animate canvas shows: re-rendered whenever any part changes (the view keys a task on it).
public struct AnimationFrameRequest: Equatable, Sendable {
    let document: EditorDocument
    let time: Double
    let isActive: Bool
    let isPlaying: Bool
    let isDark: Bool
}

/// S13: Animate mode, the playhead, playback and clip editing. Every document change goes through `perform`
/// (one undo step); the frame at the playhead is rendered off the main actor by `AnimationRenderer` (that is,
/// `Renderer.render`) at preview scale.
extension EditorModel {
    public var canAnimate: Bool { hasContent }
    public var timeline: AnimationTimeline { project.timeline }
    public var animationDuration: Double { AnimationRenderer.duration(of: session.document) }
    public var hasVideoContent: Bool { session.document.activeVideo != nil }
    public var isMuted: Bool { timeline.isMuted }

    public var selectedClip: AnimationClip? {
        guard let id = animate.selectedClipID else { return nil }
        return timeline.clips.first { $0.id == id }
    }

    /// `00:01.50 / 00:03.00`.
    public var timecodeText: String {
        "\(TimecodeFormat.clock(animate.playhead)) / \(TimecodeFormat.clock(animationDuration))"
    }

    /// The canvas image: the frame at the playhead in Animate mode, the still preview otherwise.
    public var displayedPreview: CGImage? {
        animate.isActive ? (animate.frame ?? preview) : preview
    }

    public var animationFrameRequest: AnimationFrameRequest {
        AnimationFrameRequest(
            document: session.document, time: animate.playhead, isActive: animate.isActive,
            isPlaying: animate.isPlaying, isDark: isDarkAppearance)
    }

    // MARK: Mode

    public func setAnimateMode(_ active: Bool) {
        guard active != animate.isActive else { return }
        if active {
            guard canAnimate else { return }
            setAnnotateMode(false)
            animate.isActive = true
            animate.playhead = min(animate.playhead, animationDuration)
        } else {
            pause()
            animate.isActive = false
            animate.frame = nil
            animate.frameDocument = nil
            animate.selectedClipID = nil
        }
    }

    public func toggleAnimateMode() { setAnimateMode(!animate.isActive) }

    // MARK: Playhead and playback

    /// Renders the frame at the playhead (no-op when it is already showing). Stale renders are dropped.
    public func renderAnimationFrame() async {
        guard animate.isActive else { return }
        let document = session.document
        let time = animate.playhead
        if animate.frame != nil, animate.frameDocument == document, animate.frameTime == time { return }
        animate.frameGeneration += 1
        let generation = animate.frameGeneration
        let source = await videoSource(for: document)
        let scale = previewScale
        let grid = SunshotPalette.transparencyGrid(dark: isDarkAppearance)
        let image = try? await Task.detached(priority: .userInitiated) {
            let frame = try source?.frame(at: time)
            return try AnimationRenderer.render(
                document, at: time, videoFrame: frame, scale: scale, showsTransparencyGrid: true, grid: grid)
        }.value
        guard generation == animate.frameGeneration, animate.isActive else { return }
        animate.frame = image ?? nil
        animate.frameDocument = document
        animate.frameTime = time
    }

    /// The decoder for the document's video content, opened once per video.
    func videoSource(for document: EditorDocument) async -> VideoFrameSource? {
        guard let video = document.activeVideo else { return nil }
        if let cached = animate.videoSource, cached.id == video.id { return cached.source }
        guard let source = try? await VideoFrameSource.open(url: video.url) else { return nil }
        animate.videoSource = (video.id, source)
        return source
    }

    /// Moves the playhead (clamped to the animation) and renders that frame. The document is untouched.
    @discardableResult
    public func seek(to time: Double) -> Task<Void, Never> {
        pause()
        animate.playhead = time.isFinite ? min(max(time, 0), animationDuration) : 0
        return Task { await renderAnimationFrame() }
    }

    @discardableResult public func seekToStart() -> Task<Void, Never> { seek(to: 0) }
    @discardableResult public func seekToEnd() -> Task<Void, Never> { seek(to: animationDuration) }

    public func togglePlayback() {
        if animate.isPlaying { pause() } else { play() }
    }

    /// Plays from the playhead (from the start when at the end) in real time; slow frames are skipped, not
    /// slowed down. Stops at the end with the playhead there.
    public func play() {
        guard animate.isActive, !animate.isPlaying else { return }
        let duration = animationDuration
        if animate.playhead >= duration { animate.playhead = 0 }
        animate.isPlaying = true
        let origin = animate.playhead
        let clock = ContinuousClock()
        let started = clock.now
        animate.playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = started.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let time = min(origin + seconds, duration)
                self.animate.playhead = time
                await self.renderAnimationFrame()
                if time >= duration || Task.isCancelled { break }
                try? await Task.sleep(for: self.animate.frameInterval)
            }
            if !Task.isCancelled { self?.animate.isPlaying = false }
        }
    }

    public func pause() {
        animate.playbackTask?.cancel()
        animate.playbackTask = nil
        animate.isPlaying = false
    }

    // MARK: Clips

    /// Adds a clip after the one under the playhead and selects it.
    @discardableResult
    public func addClip() -> Task<Void, Never> {
        var id: UUID?
        let task = perform { id = $0.addClip(at: animate.playhead) }
        animate.selectedClipID = id
        return task
    }

    public func selectClip(_ id: UUID?) {
        animate.selectedClipID = id
        guard let id, let index = timeline.clips.firstIndex(where: { $0.id == id }) else { return }
        let clip = timeline.clips[index]
        seek(to: timeline.startTime(ofClip: index) + Double(clip.durationMS) / 1000)
    }

    public func deleteSelectedClip() {
        guard let id = animate.selectedClipID else { return }
        perform { $0.removeClip(id: id) }
        animate.selectedClipID = nil
        animate.playhead = min(animate.playhead, animationDuration)
    }

    public func moveSelectedClip(by offset: Int) {
        guard let id = animate.selectedClipID else { return }
        perform { $0.moveClip(id: id, by: offset) }
    }

    public func setEasing(_ easing: AnimationEasing) {
        guard let id = animate.selectedClipID else { return }
        perform { $0.setClipEasing(id: id, easing) }
    }

    /// Slider changes: wrap a drag in `beginGesture` / `endGesture(EditorSession.clipDurationActionName)`.
    public func setClipDuration(milliseconds: Int) {
        guard let id = animate.selectedClipID else { return }
        apply { $0.setClipDuration(id: id, milliseconds: milliseconds) }
    }

    public func setClipHold(milliseconds: Int) {
        guard let id = animate.selectedClipID else { return }
        apply { $0.setClipHold(id: id, milliseconds: milliseconds) }
    }

    /// The selected clip's target (position, zoom, rotation, tilt).
    public func setClipTarget(_ change: (inout ContentTransform) -> Void) {
        guard let clip = selectedClip else { return }
        var target = clip.target
        change(&target)
        apply { $0.setClipTarget(id: clip.id, target) }
    }

    /// Copies the canvas's own layout into the selected clip's target.
    public func setClipTargetToCurrentLayout() {
        let transform = session.contentTransform
        setClipTarget { $0 = transform }
    }

    public func toggleMute() {
        let muted = !isMuted
        perform { $0.setMuted(muted) }
    }
}
