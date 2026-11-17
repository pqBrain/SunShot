import Foundation
import Testing

@testable import SunshotCore

@Suite("Animation timeline")
struct AnimationTimelineTests {
    static let start = ContentTransform(x: 0.1, zoom: 100, rotation: 170)
    static let targetA = ContentTransform(x: -0.2, y: 0.1, zoom: 150, rotation: -170, tiltX: 20, tiltY: -10)
    static let targetB = ContentTransform(zoom: 80, rotation: 30)

    static func timeline(easing: AnimationEasing = .linear) -> AnimationTimeline {
        AnimationTimeline(clips: [
            AnimationClip(target: targetA, durationMS: 1000, holdMS: 500, easing: easing),
            AnimationClip(target: targetB, durationMS: 600, holdMS: 0, easing: easing),
        ])
    }

    @Test("[S13-AC1] an unused timeline is not encoded and a missing key decodes to the defaults")
    func defaultsAreInvisible() throws {
        let project = Project()
        #expect(project.animation == nil)
        let json = try JSONEncoder().encode(project)
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("animation"))
        let decoded = try JSONDecoder().decode(Project.self, from: json)
        #expect(decoded == project)
        let timeline = decoded.timeline
        #expect(timeline.clips.isEmpty && timeline.leadInMS == 500 && !timeline.isMuted)
        #expect(timeline.video == VideoExportOptions(resolution: .hd, frameRate: .fps30, codec: .h264))
        var edited = project
        edited.timeline = AnimationTimeline()
        #expect(edited.animation == nil)
    }

    @Test("[S13-AC1] timelines round-trip and decode tolerantly (bad clips skipped, bad values defaulted)")
    func tolerantDecoding() throws {
        var project = Project()
        project.timeline = Self.timeline(easing: .outCirc)
        project.timeline.isMuted = true
        project.timeline.video = VideoExportOptions(resolution: .twoK, frameRate: .fps60, codec: .hevc)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(decoded.timeline == project.timeline)

        let json = """
            {"clips": [{"durationMS": 99999, "easing": "wobble"}, 7, {"target": {"zoom": 200}}],
             "leadInMS": "x", "video": {"frameRate": 24, "codec": "hevc"}}
            """
        let timeline = try JSONDecoder().decode(AnimationTimeline.self, from: Data(json.utf8))
        #expect(timeline.clips.count == 2)
        #expect(timeline.clips[0].durationMS == 10_000 && timeline.clips[0].easing == .spring)
        #expect(timeline.clips[1].target.zoom == 200 && timeline.clips[1].holdMS == 500)
        #expect(timeline.leadInMS == 500)
        #expect(timeline.video == VideoExportOptions(resolution: .hd, frameRate: .fps30, codec: .hevc))
    }

    @Test("[S13-AC2] transform(at:) is exact at keyframes, in between for linear, and deterministic")
    func keyframesExact() {
        let timeline = Self.timeline()
        #expect(timeline.transform(at: 0, from: Self.start) == Self.start)
        #expect(timeline.transform(at: 0.5, from: Self.start) == Self.start)
        #expect(timeline.transform(at: 1.5, from: Self.start) == Self.targetA)
        #expect(timeline.transform(at: 1.8, from: Self.start) == Self.targetA)
        #expect(timeline.transform(at: 2.0, from: Self.start) == Self.targetA)
        #expect(timeline.transform(at: 2.6, from: Self.start) == Self.targetB)
        #expect(timeline.transform(at: 50, from: Self.start) == Self.targetB)
        #expect(timeline.transform(at: .nan, from: Self.start) == Self.targetB)

        let mid = timeline.transform(at: 1.0, from: Self.start)
        #expect(abs(mid.x - (-0.05)) < 1e-9 && abs(mid.zoom - 125) < 1e-9 && abs(mid.tiltX - 10) < 1e-9)
        #expect(abs(abs(mid.rotation) - 180) < 1e-9, "rotation takes the short way through 180°")
        #expect(timeline.transform(at: 1.234, from: Self.start) == timeline.transform(at: 1.234, from: Self.start))

        #expect(abs(timeline.animationLength - 2.6) < 1e-9)
        #expect(abs(timeline.startTime(ofClip: 1) - 2.0) < 1e-9)
        #expect(timeline.clipIndex(at: 0.2) == nil && timeline.clipIndex(at: 1.9) == 0)
        #expect(timeline.clipIndex(at: 2.0) == 1 && timeline.clipIndex(at: 3) == nil)
        #expect(timeline.state(afterClip: -1, from: Self.start) == Self.start)
        #expect(timeline.state(afterClip: 5, from: Self.start) == Self.targetB)
    }

    @Test("[S13-AC2] [S13-AC3] every easing hits the targets exactly; monotonic easings stay between them")
    func everyEasingIsExact() {
        for easing in AnimationEasing.allCases {
            let timeline = Self.timeline(easing: easing)
            #expect(timeline.transform(at: 1.5, from: Self.start) == Self.targetA, "\(easing)")
            #expect(timeline.transform(at: 2.6, from: Self.start) == Self.targetB, "\(easing)")
            guard easing.isMonotonic else { continue }
            for step in 1..<20 {
                let zoom = timeline.transform(at: 0.5 + Double(step) / 20, from: Self.start).zoom
                #expect(zoom >= 100 && zoom <= 150, "\(easing) \(zoom)")
            }
        }
    }

    @Test("[S13-AC3] easing curves: exact ends, monotonic within 0…1, spring overshoots ≤ 8 % and settles")
    func easingCurves() {
        #expect(AnimationEasing.allCases.count == 6)
        for easing in AnimationEasing.allCases {
            #expect(easing.value(at: 0) == 0 && easing.value(at: 1) == 1, "\(easing)")
            #expect(easing.value(at: -1) == 0 && easing.value(at: 2) == 1 && easing.value(at: .infinity) == 1)
            let samples = (0...1000).map { easing.value(at: Double($0) / 1000) }
            if easing.isMonotonic {
                #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 }, "\(easing)")
                #expect(samples.allSatisfy { (0...1).contains($0) }, "\(easing)")
            } else {
                let peak = samples.max() ?? 0
                #expect(peak > 1 && peak <= 1.08, "spring peak \(peak)")
                #expect(samples[800...].allSatisfy { abs($0 - 1) <= 0.02 }, "spring settles")
            }
        }
        #expect(AnimationEasing.linear.value(at: 0.25) == 0.25)
        #expect(AnimationEasing.out.value(at: 0.5) > 0.5 && AnimationEasing.cubic.value(at: 0.25) < 0.25)
        #expect(abs(AnimationEasing.inOut.value(at: 0.5) - 0.5) < 1e-12)
    }

    @Test("[S13-AC3] a spring overshoot stays within the transform's ranges")
    func springOvershootIsClamped() {
        let from = ContentTransform(x: 0.4, zoom: 390)
        let to = ContentTransform(x: 0.5, zoom: 400)
        let over = from.blended(to: to, progress: 1.05)
        #expect(over.x == 0.5 && over.zoom == 400)
        #expect(from.blended(to: to, progress: 0) == from && from.blended(to: to, progress: .nan) == to)
        let under = ContentTransform(zoom: 100).blended(to: ContentTransform(zoom: 200), progress: 1.04)
        #expect(abs(under.zoom - 204) < 1e-9, "overshoot is not rounded to whole percent")
    }

    @Test("[S13-AC4] a zero-duration clip is a jump cut")
    func jumpCut() {
        let timeline = AnimationTimeline(clips: [
            AnimationClip(target: Self.targetA, durationMS: 0, holdMS: 1000, easing: .spring)
        ])
        #expect(timeline.clips[0].isJumpCut)
        #expect(timeline.transform(at: 0.4999, from: Self.start) == Self.start)
        #expect(timeline.transform(at: 0.5, from: Self.start) == Self.targetA)
        #expect(timeline.transform(at: 1.2, from: Self.start) == Self.targetA)
    }

    @Test("[S13-AC6] total length: longest of animation and content, between 1 s and 2 minutes")
    func durationLimits() {
        let long = AnimationTimeline(
            clips: (0..<20).map { _ in AnimationClip(target: Self.targetA, durationMS: 10_000, holdMS: 10_000) })
        #expect(long.animationLength > 120)
        #expect(long.duration() == 120)
        #expect(AnimationTimeline().duration() == 1)
        #expect(AnimationTimeline().duration(contentDuration: 7.5) == 7.5)
        #expect(AnimationTimeline().duration(contentDuration: 600) == 120)
        #expect(Self.timeline().duration(contentDuration: .nan) == 2.6)
        var clip = AnimationClip(target: .identity, durationMS: -5, holdMS: 20_000)
        #expect(clip.durationMS == 0 && clip.holdMS == 10_000)
        clip.durationMS = 12_000
        #expect(clip.durationMS == 10_000)
    }
}
