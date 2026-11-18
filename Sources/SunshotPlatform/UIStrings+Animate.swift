public import SunshotCore

/// S13: Animate mode, timeline and video export copy and accessibility labels.
extension UIStrings {
    public static let animate = "Animate"
    public static let animateAccessibility = "Animate: keyframe timeline and video export, ⇧⌘M"
    public static let exitAnimate = "Exit Animate"
    public static let addAnimation = "Add Animation"
    public static let addAnimationAccessibility = "Add an animation clip after the playhead"
    public static let deleteAnimation = "Delete Animation"
    public static let play = "Play"
    public static let pause = "Pause"
    public static let playAccessibility = "Play or pause, Space"
    public static let mute = "Mute"
    public static let unmute = "Unmute"
    public static let muteAccessibility = "Mute or unmute the video's sound"
    public static let transition = "Transition"
    public static let easingSection = "Easing"
    public static let durationSlider = "Duration"
    public static let holdSlider = "Hold"
    public static let clipTarget = "Target"
    public static let useCanvasLayout = "Use Canvas Layout"
    public static let moveEarlier = "Move Earlier"
    public static let moveLater = "Move Later"
    public static let jumpCut = "Jump cut"
    public static let timelineAccessibility = "Animation timeline"
    public static let playheadAccessibility = "Playhead"
    public static let noClipsHint = "Add an animation to move, zoom or tilt the content over time"

    public static let importVideo = "Import Video…"
    public static let exportVideo = "Export Video…"
    public static let exportVideoTitle = "Export Video"
    public static let resolutionPicker = "Resolution"
    public static let frameRatePicker = "Frame rate"
    public static let codecPicker = "Codec"
    public static let durationRow = "Duration"
    public static let movWithAlpha = ".mov (HEVC with alpha)"
    public static let transparentVideoHint = "The backdrop is see-through, so the video keeps transparency."
    public static let cancelRender = "Cancel Render"
    public static let rendering = "Rendering…"
    public static let videoExported = "Video exported"
    public static let videoExportCancelled = "Video export cancelled"

    public static func easingLabel(_ easing: AnimationEasing) -> String {
        switch easing {
        case .spring: "Spring"
        case .linear: "Linear"
        case .cubic: "Cubic"
        case .out: "Out"
        case .inOut: "In Out"
        case .outCirc: "Out Circ"
        }
    }

    /// `1000ms`.
    public static func milliseconds(_ value: Int) -> String { "\(value)ms" }

    public static func clipAccessibility(index: Int, clip: AnimationClip) -> String {
        let timing = clip.isJumpCut ? jumpCut : "\(easingLabel(clip.easing)), \(milliseconds(clip.durationMS))"
        return "Animation \(index + 1): \(timing), zoom \(Int(clip.target.zoom.rounded())) %"
    }
}
