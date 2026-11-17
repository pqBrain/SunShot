public import Foundation
public import SunshotCore

/// S13: timeline edits. Each is one named undo step (slider drags are coalesced with `beginGesture` /
/// `endGesture`); edits that change nothing record nothing.
extension EditorSession {
    public static let addClipActionName = "Add Animation"
    public static let deleteClipActionName = "Delete Animation"
    public static let moveClipActionName = "Move Animation"
    public static let easingActionName = "Change Easing"
    public static let clipDurationActionName = "Change Duration"
    public static let clipHoldActionName = "Change Hold"
    public static let clipTargetActionName = "Change Animation Target"
    public static let muteActionName = "Mute Audio"
    public static let unmuteActionName = "Unmute Audio"
    public static let videoOptionsActionName = "Change Video Options"
    /// A new clip zooms in this much from the state before it.
    public static let newClipZoomFactor = 1.2

    public var timeline: AnimationTimeline { document.project.timeline }

    /// Inserts a clip after the clip under `time` (at the start during the lead-in, at the end past the last
    /// clip): 1000 ms, spring, target = the state there zoomed in 20 %. Returns its id.
    @discardableResult
    public mutating func addClip(at time: Double) -> UUID {
        let timeline = self.timeline
        let index: Int
        if let current = timeline.clipIndex(at: time) {
            index = current + 1
        } else {
            index = time < timeline.leadIn ? 0 : timeline.clips.count
        }
        var target = timeline.state(afterClip: index - 1, from: contentTransform)
        target.zoom *= Self.newClipZoomFactor
        let clip = AnimationClip(target: target)
        editTimeline(Self.addClipActionName) { $0.clips.insert(clip, at: index) }
        return clip.id
    }

    public mutating func removeClip(id: UUID) {
        editTimeline(Self.deleteClipActionName) { $0.clips.removeAll { $0.id == id } }
    }

    /// Moves a clip `offset` places (−1 earlier, +1 later); clamped to the ends (no entry if it can't move).
    public mutating func moveClip(id: UUID, by offset: Int) {
        editTimeline(Self.moveClipActionName) { timeline in
            guard let from = timeline.clips.firstIndex(where: { $0.id == id }) else { return }
            let to = min(max(from + offset, 0), timeline.clips.count - 1)
            guard to != from else { return }
            let clip = timeline.clips.remove(at: from)
            timeline.clips.insert(clip, at: to)
        }
    }

    public mutating func setClipEasing(id: UUID, _ easing: AnimationEasing) {
        editClip(id, Self.easingActionName) { $0.easing = easing }
    }

    /// Duration in ms (0…10 000; 0 = jump cut).
    public mutating func setClipDuration(id: UUID, milliseconds: Int) {
        editClip(id, Self.clipDurationActionName) { $0.durationMS = milliseconds }
    }

    public mutating func setClipHold(id: UUID, milliseconds: Int) {
        editClip(id, Self.clipHoldActionName) { $0.holdMS = milliseconds }
    }

    public mutating func setClipTarget(id: UUID, _ target: ContentTransform) {
        editClip(id, Self.clipTargetActionName) { $0.target = target }
    }

    public mutating func setMuted(_ muted: Bool) {
        editTimeline(muted ? Self.muteActionName : Self.unmuteActionName) { $0.isMuted = muted }
    }

    public mutating func setVideoExportOptions(_ options: VideoExportOptions) {
        editTimeline(Self.videoOptionsActionName) { $0.video = options }
    }

    private mutating func editClip(_ id: UUID, _ name: String, _ change: (inout AnimationClip) -> Void) {
        editTimeline(name) { timeline in
            guard let index = timeline.clips.firstIndex(where: { $0.id == id }) else { return }
            change(&timeline.clips[index])
        }
    }

    private mutating func editTimeline(_ name: String, _ change: (inout AnimationTimeline) -> Void) {
        editProject(name) { project in
            var timeline = project.timeline
            change(&timeline)
            project.timeline = timeline
        }
    }
}
