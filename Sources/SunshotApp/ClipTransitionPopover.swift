import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// The selected clip's transition: easing presets with curve previews, duration and hold, and the target state
/// (position, zoom, rotation, tilt). Slider drags are single undo steps.
struct ClipTransitionPopover: View {
    let model: EditorModel

    var body: some View {
        if let clip = model.selectedClip {
            VStack(alignment: .leading, spacing: 12) {
                Text(UIStrings.easingSection).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 8), count: 3), spacing: 8) {
                    ForEach(AnimationEasing.allCases, id: \.self) { easing in
                        easingButton(easing, selected: clip.easing == easing)
                    }
                }
                msSlider(
                    UIStrings.durationSlider, value: clip.durationMS, actionName: EditorSession.clipDurationActionName
                ) { model.setClipDuration(milliseconds: $0) }
                msSlider(UIStrings.holdSlider, value: clip.holdMS, actionName: EditorSession.clipHoldActionName) {
                    model.setClipHold(milliseconds: $0)
                }
                Divider()
                HStack {
                    Text(UIStrings.clipTarget).font(.headline)
                    Spacer()
                    Button(UIStrings.useCanvasLayout) { model.setClipTargetToCurrentLayout() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                targetSlider("X", clip.target.x * 100, -50...50) { value in model.setClipTarget { $0.x = value / 100 } }
                targetSlider("Y", clip.target.y * 100, -50...50) { value in model.setClipTarget { $0.y = value / 100 } }
                targetSlider(UIStrings.zoomLabel, clip.target.zoom, ContentTransform.zoomRange) { value in
                    model.setClipTarget { $0.zoom = value }
                }
                targetSlider(UIStrings.rotationLabel, clip.target.rotation, ContentTransform.rotationRange) { value in
                    model.setClipTarget { $0.rotation = value.rounded() }
                }
                targetSlider(UIStrings.tiltXLabel, clip.target.tiltX, ContentTransform.tiltRange) { value in
                    model.setClipTarget { $0.tiltX = value.rounded() }
                }
                targetSlider(UIStrings.tiltYLabel, clip.target.tiltY, ContentTransform.tiltRange) { value in
                    model.setClipTarget { $0.tiltY = value.rounded() }
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    private func easingButton(_ easing: AnimationEasing, selected: Bool) -> some View {
        Button {
            model.setEasing(easing)
        } label: {
            VStack(spacing: 4) {
                EasingCurve(easing: easing)
                    .stroke(selected ? Color.accentColor : .secondary, lineWidth: 1.5)
                    .frame(width: 44, height: 28)
                Text(UIStrings.easingLabel(easing)).font(.caption2)
            }
            .frame(width: 70, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UIStrings.easingLabel(easing))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func msSlider(
        _ title: String, value: Int, actionName: String, set: @escaping @MainActor (Int) -> Void
    ) -> some View {
        HStack {
            Text(title).font(.callout).frame(width: 64, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value) }, set: { set(Int(($0 / 50).rounded()) * 50) }),
                in: Double(AnimationClip.durationRangeMS.lowerBound)...Double(AnimationClip.durationRangeMS.upperBound)
            ) {
                Text(title)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(actionName)
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(UIStrings.milliseconds(value))
            Text(UIStrings.milliseconds(value)).font(.callout.monospacedDigit()).frame(width: 64, alignment: .trailing)
        }
    }

    private func targetSlider(
        _ title: String, _ value: Double, _ range: ClosedRange<Double>, set: @escaping @MainActor (Double) -> Void
    ) -> some View {
        HStack {
            Text(title).font(.callout).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range) {
                Text(title)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(EditorSession.clipTargetActionName)
            }
            .labelsHidden()
            .accessibilityLabel("\(UIStrings.clipTarget) \(title)")
            Text("\(Int(value.rounded()))").font(.callout.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
    }
}

/// The easing curve over 0…1, for the preset buttons.
struct EasingCurve: Shape {
    let easing: AnimationEasing

    func path(in rect: CGRect) -> Path {
        Path { path in
            let steps = 40
            // Leave headroom for the spring's overshoot.
            let height = rect.height * 0.85
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let point = CGPoint(
                    x: rect.minX + rect.width * t, y: rect.maxY - height * easing.value(at: t))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }
}
