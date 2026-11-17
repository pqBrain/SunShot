import SunshotCore
import SunshotPlatform
import SwiftUI

/// Animate mode's glass strip under the canvas: transport (exit, mute, add, play, time, transition, delete),
/// a scrubber and the clip track. Space plays/pauses, Home/End seek, ⌫ deletes the selected clip.
struct AnimateTimelineView: View {
    let model: EditorModel
    @State private var showsTransition = false
    @FocusState private var isFocused: Bool

    private var animate: AnimateState { model.animate }

    var body: some View {
        VStack(spacing: 10) {
            transport
            scrubber
            ClipTrack(model: model)
        }
        .padding(12)
        .frame(maxWidth: 720)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space) {
            model.togglePlayback()
            return .handled
        }
        .onKeyPress(.home) {
            model.seekToStart()
            return .handled
        }
        .onKeyPress(.end) {
            model.seekToEnd()
            return .handled
        }
        .onKeyPress(.delete) {
            model.deleteSelectedClip()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.timelineAccessibility)
    }

    private var transport: some View {
        HStack(spacing: 8) {
            iconButton(UIStrings.exitAnimate, "chevron.left") { model.setAnimateMode(false) }
            iconButton(
                model.isMuted ? UIStrings.unmute : UIStrings.mute,
                model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            ) { model.toggleMute() }
            .disabled(!model.hasVideoContent)
            .accessibilityHint(UIStrings.muteAccessibility)
            Button {
                model.addClip()
            } label: {
                Label(UIStrings.addAnimation, systemImage: "plus")
            }
            .buttonStyle(.glass)
            .help(UIStrings.addAnimationAccessibility)
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: animate.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .buttonStyle(.glassProminent)
            .help(UIStrings.playAccessibility)
            .accessibilityLabel(animate.isPlaying ? UIStrings.pause : UIStrings.play)
            Text(model.timecodeText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(model.timecodeText)
            Spacer(minLength: 8)
            if let clip = model.selectedClip {
                Button(UIStrings.milliseconds(clip.durationMS)) { showsTransition.toggle() }
                    .buttonStyle(.glass)
                    .help(UIStrings.transition)
                    .accessibilityLabel("\(UIStrings.transition), \(UIStrings.milliseconds(clip.durationMS))")
                    .popover(isPresented: $showsTransition, arrowEdge: .top) {
                        ClipTransitionPopover(model: model)
                    }
                iconButton(UIStrings.deleteAnimation, "trash") { model.deleteSelectedClip() }
            }
            iconButton(UIStrings.exportVideo, "square.and.arrow.up.on.square") { animate.showsExportSheet = true }
                .disabled(!model.canExportVideo)
        }
    }

    private var scrubber: some View {
        Slider(
            value: Binding(get: { animate.playhead }, set: { model.seek(to: $0) }),
            in: 0...max(model.animationDuration, 0.01)
        )
        .controlSize(.small)
        .accessibilityLabel(UIStrings.playheadAccessibility)
        .accessibilityValue(model.timecodeText)
    }

    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.glass)
            .help(title)
            .accessibilityLabel(title)
    }
}

/// One chip per clip, width ∝ its length; the lead-in is a spacer. Tap selects; the context menu reorders.
struct ClipTrack: View {
    let model: EditorModel

    var body: some View {
        let timeline = model.timeline
        GeometryReader { proxy in
            let total = max(model.animationDuration, 0.01)
            let unit = proxy.size.width / total
            HStack(spacing: 2) {
                Color.clear.frame(width: max(0, timeline.leadIn * unit - 2))
                ForEach(Array(timeline.clips.enumerated()), id: \.element.id) { index, clip in
                    chip(index: index, clip: clip).frame(width: max(14, clip.length * unit - 2))
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .offset(x: model.animate.playhead * unit)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 34)
        .overlay {
            if timeline.clips.isEmpty {
                Text(UIStrings.noClipsHint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chip(index: Int, clip: AnimationClip) -> some View {
        let selected = model.animate.selectedClipID == clip.id
        return Button {
            model.selectClip(clip.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: clip.isJumpCut ? "scissors" : "waveform.path")
                Text(clip.isJumpCut ? UIStrings.jumpCut : UIStrings.easingLabel(clip.easing)).lineLimit(1)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(selected ? 0.35 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UIStrings.clipAccessibility(index: index, clip: clip))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(UIStrings.moveEarlier) {
                model.selectClip(clip.id)
                model.moveSelectedClip(by: -1)
            }
            Button(UIStrings.moveLater) {
                model.selectClip(clip.id)
                model.moveSelectedClip(by: 1)
            }
            Divider()
            Button(UIStrings.deleteAnimation) {
                model.selectClip(clip.id)
                model.deleteSelectedClip()
            }
        }
    }
}
