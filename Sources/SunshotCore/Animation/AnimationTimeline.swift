public import Foundation

/// One keyframe clip: animate the content transform from the previous state to `target` over `durationMS` with
/// `easing`, then hold `target` for `holdMS`. A duration of 0 is a jump cut (the target appears at once).
public struct AnimationClip: Hashable, Sendable, Identifiable {
    public static let durationRangeMS: ClosedRange<Int> = 0...10_000
    public static let defaultDurationMS = 1000
    public static let defaultHoldMS = 500

    public var id: UUID
    public var target: ContentTransform
    public var durationMS: Int { didSet { durationMS = Self.clampMS(durationMS) } }
    public var holdMS: Int { didSet { holdMS = Self.clampMS(holdMS) } }
    public var easing: AnimationEasing

    public init(
        id: UUID = UUID(), target: ContentTransform, durationMS: Int = AnimationClip.defaultDurationMS,
        holdMS: Int = AnimationClip.defaultHoldMS, easing: AnimationEasing = .defaultEasing
    ) {
        self.id = id
        self.target = target
        self.durationMS = Self.clampMS(durationMS)
        self.holdMS = Self.clampMS(holdMS)
        self.easing = easing
    }

    public var isJumpCut: Bool { durationMS == 0 }
    /// Transition plus hold, in seconds.
    public var length: Double { Double(durationMS + holdMS) / 1000 }

    public static func clampMS(_ value: Int) -> Int {
        min(max(value, durationRangeMS.lowerBound), durationRangeMS.upperBound)
    }
}

extension AnimationClip: Codable {
    private enum CodingKeys: String, CodingKey { case id, target, durationMS, holdMS, easing }

    /// Tolerant: any missing or invalid value takes its default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID(),
            target: ((try? container.decodeIfPresent(ContentTransform.self, forKey: .target)) ?? nil) ?? .identity,
            durationMS: ((try? container.decodeIfPresent(Int.self, forKey: .durationMS)) ?? nil)
                ?? Self.defaultDurationMS,
            holdMS: ((try? container.decodeIfPresent(Int.self, forKey: .holdMS)) ?? nil) ?? Self.defaultHoldMS,
            easing: ((try? container.decodeIfPresent(AnimationEasing.self, forKey: .easing)) ?? nil)
                ?? .defaultEasing)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(target, forKey: .target)
        try container.encode(durationMS, forKey: .durationMS)
        try container.encode(holdMS, forKey: .holdMS)
        try container.encode(easing, forKey: .easing)
    }
}

/// The document's animation: a lead-in, then clips played back to back, plus mute and video export options.
/// The start state is the document's own transform (`Project.placement.transform`), so an empty timeline shows
/// the still layout. Pure and deterministic: the same time always gives the same transform.
public struct AnimationTimeline: Hashable, Sendable {
    /// Longest animation or video Sunshot exports, in seconds.
    public static let maxDuration: Double = 120
    /// Shortest export (a timeline with no clips and no video still exports one second).
    public static let minDuration: Double = 1
    public static let defaultLeadInMS = 500

    public var clips: [AnimationClip]
    /// Time the start state is shown before the first clip begins.
    public var leadInMS: Int { didSet { leadInMS = AnimationClip.clampMS(leadInMS) } }
    /// Leave the video content's audio out of the export.
    public var isMuted: Bool
    public var video: VideoExportOptions

    public init(
        clips: [AnimationClip] = [], leadInMS: Int = AnimationTimeline.defaultLeadInMS, isMuted: Bool = false,
        video: VideoExportOptions = VideoExportOptions()
    ) {
        self.clips = clips
        self.leadInMS = AnimationClip.clampMS(leadInMS)
        self.isMuted = isMuted
        self.video = video
    }

    public var leadIn: Double { Double(leadInMS) / 1000 }

    /// Lead-in plus every clip's transition and hold, in seconds (uncapped).
    public var animationLength: Double { leadIn + clips.reduce(0) { $0 + $1.length } }

    /// Export length: the longer of the animation and the content (`contentDuration`, video only), at least
    /// `minDuration` and at most `maxDuration`.
    public func duration(contentDuration: Double? = nil) -> Double {
        let content = contentDuration.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return min(max(animationLength, content, Self.minDuration), Self.maxDuration)
    }

    /// When clip `index` starts its transition (seconds); the animation's end for `index == clips.count`.
    public func startTime(ofClip index: Int) -> Double {
        leadIn + clips.prefix(max(0, min(index, clips.count))).reduce(0) { $0 + $1.length }
    }

    /// The clip whose transition or hold contains `time`, if any.
    public func clipIndex(at time: Double) -> Int? {
        guard time.isFinite else { return nil }
        var cursor = leadIn
        for (index, clip) in clips.enumerated() {
            let end = cursor + clip.length
            if time >= cursor && time < end { return index }
            cursor = end
        }
        return nil
    }

    /// The state reached after clip `index` (the start state for −1).
    public func state(afterClip index: Int, from start: ContentTransform) -> ContentTransform {
        guard index >= 0, !clips.isEmpty else { return start }
        return clips[min(index, clips.count - 1)].target
    }

    /// The content transform at `time` seconds for a timeline starting from `start`. Exact at every keyframe:
    /// `start` until the lead-in ends, each clip's target from its transition's end through its hold.
    public func transform(at time: Double, from start: ContentTransform) -> ContentTransform {
        guard time.isFinite else { return clips.last?.target ?? start }
        var current = start
        var cursor = leadIn
        if time < cursor { return start }
        for clip in clips {
            let duration = Double(clip.durationMS) / 1000
            if duration > 0 && time < cursor + duration {
                let progress = clip.easing.value(at: (time - cursor) / duration)
                return current.blended(to: clip.target, progress: progress)
            }
            current = clip.target
            cursor += duration + Double(clip.holdMS) / 1000
            if time < cursor { return current }
        }
        return current
    }
}

extension AnimationTimeline: Codable {
    private enum CodingKeys: String, CodingKey { case clips, leadInMS, isMuted, video }

    /// Tolerant: missing values take their defaults; unreadable clips are skipped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let clips = ((try? container.decodeIfPresent([LenientClip].self, forKey: .clips)) ?? nil) ?? []
        self.init(
            clips: clips.compactMap(\.clip),
            leadInMS: ((try? container.decodeIfPresent(Int.self, forKey: .leadInMS)) ?? nil) ?? Self.defaultLeadInMS,
            isMuted: ((try? container.decodeIfPresent(Bool.self, forKey: .isMuted)) ?? nil) ?? false,
            video: ((try? container.decodeIfPresent(VideoExportOptions.self, forKey: .video)) ?? nil)
                ?? VideoExportOptions())
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clips, forKey: .clips)
        try container.encode(leadInMS, forKey: .leadInMS)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(video, forKey: .video)
    }

    private struct LenientClip: Decodable {
        let clip: AnimationClip?
        init(from decoder: any Decoder) throws { clip = try? AnimationClip(from: decoder) }
    }
}

extension Project {
    /// The animation timeline (S13). Stored as nil while it is the default, so a document that never used Animate
    /// encodes exactly as before.
    public var timeline: AnimationTimeline {
        get { animation ?? AnimationTimeline() }
        set { animation = newValue == AnimationTimeline() ? nil : newValue }
    }

    /// Whether the backdrop lets the content's surroundings show through (exports keep alpha).
    public var hasTransparentBackdrop: Bool {
        !backdrop.isOpaque || backdropSettings.effects.adjustments.opacity < 1
    }
}
