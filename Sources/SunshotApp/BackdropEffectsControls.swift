import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// S8: the "Effects" subsection of the Backdrop section: four glass buttons, each opening a popover.
struct BackdropEffectsControls: View {
    let model: EditorModel

    private var effects: BackdropEffects { model.project.backdropSettings.effects }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ControlCaption(UIStrings.effects)
            HStack(spacing: 6) {
                EffectButton(
                    title: UIStrings.overlayButton, systemImage: "sun.max",
                    value: UIStrings.overlayName(effects.overlay.kind), isOn: !effects.overlay.isIdentity
                ) { OverlayPopover(model: model) }
                EffectButton(
                    title: UIStrings.adjustButton, systemImage: "slider.horizontal.3",
                    value: UIStrings.adjustSummary(effects.adjustments),
                    isOn: !effects.adjustments.isIdentity
                ) { AdjustPopover(model: model) }
                EffectButton(
                    title: UIStrings.patternButton, systemImage: "circle.grid.3x3",
                    value: UIStrings.patternName(effects.pattern.kind), isOn: !effects.pattern.isIdentity
                ) { PatternPopover(model: model) }
                EffectButton(
                    title: UIStrings.vignetteButton, systemImage: "camera.aperture",
                    value: UIStrings.vignetteName(effects.vignette.style), isOn: !effects.vignette.isIdentity
                ) { VignettePopover(model: model) }
            }
        }
    }
}

/// A glass button with an "on" dot that opens its popover.
struct EffectButton<Content: View>: View {
    let title: String
    let systemImage: String
    let value: String
    let isOn: Bool
    @ViewBuilder let content: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Circle().fill(Color(nsColor: SunshotPalette.selectionRing)).frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.glass)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content().padding(16).frame(width: 300)
        }
        .accessibilityLabel(UIStrings.effectButton(title, value: value, isOn: isOn))
    }
}

/// A labelled slider whose drag is one undo step. `isPixels` shows "12 px", otherwise "40 %".
struct EffectSlider: View {
    let model: EditorModel
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var isPixels = false
    let actionName: String
    let set: (inout EditorSession, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(isPixels ? UIStrings.effectPixels(value) : UIStrings.effectPercent(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        let stepped = isPixels ? newValue.rounded() : (newValue * 100).rounded() / 100
                        model.perform { set(&$0, stepped) }
                    }),
                in: range
            ) {
                Text(title)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(actionName)
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(
                isPixels
                    ? UIStrings.effectSliderAccessibility(title, pixels: value)
                    : UIStrings.effectSliderAccessibility(title, percent: value))
        }
    }
}

/// Header row of a popover: title and its own Reset.
struct EffectPopoverHeader: View {
    let title: String
    let reset: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(UIStrings.reset, action: reset)
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel(UIStrings.resetSection(title))
        }
    }
}

struct AdjustPopover: View {
    let model: EditorModel

    private var adjustments: BackdropAdjustments { model.project.backdropSettings.effects.adjustments }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EffectPopoverHeader(title: UIStrings.adjustButton) { model.perform { $0.resetAdjustments() } }
            EffectSlider(
                model: model, title: UIStrings.effectBlur, value: adjustments.blur,
                range: BackdropAdjustments.blurRange, isPixels: true, actionName: EditorSession.blurActionName
            ) { $0.setBackdropBlur($1) }
            EffectSlider(
                model: model, title: UIStrings.effectNoise, value: adjustments.noise,
                range: BackdropAdjustments.noiseRange, actionName: EditorSession.noiseActionName
            ) { $0.setBackdropNoise($1) }
            EffectSlider(
                model: model, title: UIStrings.effectSaturation, value: adjustments.saturation,
                range: BackdropAdjustments.saturationRange, actionName: EditorSession.saturationActionName
            ) { $0.setBackdropSaturation($1) }
            EffectSlider(
                model: model, title: UIStrings.effectOpacity, value: adjustments.opacity,
                range: BackdropAdjustments.opacityRange, actionName: EditorSession.backdropOpacityActionName
            ) { $0.setBackdropOpacity($1) }
            Text(UIStrings.adjustHint)
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
        }
    }
}

struct PatternPopover: View {
    let model: EditorModel

    private var pattern: BackdropPattern { model.project.backdropSettings.effects.pattern }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EffectPopoverHeader(title: UIStrings.patternButton) { model.perform { $0.resetPattern() } }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PatternKind.allCases, id: \.self) { kind in
                    let selected = pattern.kind == kind
                    BackdropTile(
                        image: kind == .none ? nil : EffectThumbnails.shared.pattern(kind),
                        label: UIStrings.effectPickerItem(
                            UIStrings.patternButton, UIStrings.patternName(kind), selected: selected),
                        isSelected: selected
                    ) { model.perform { $0.setPatternKind(kind) } }
                }
            }
            Group {
                EffectSlider(
                    model: model, title: UIStrings.effectIntensity, value: pattern.intensity,
                    range: BackdropPattern.intensityRange, actionName: EditorSession.patternIntensityActionName
                ) { $0.setPatternIntensity($1) }
                EffectSlider(
                    model: model, title: UIStrings.effectThickness, value: pattern.thickness,
                    range: BackdropPattern.thicknessRange, actionName: EditorSession.patternThicknessActionName
                ) { $0.setPatternThickness($1) }
                HStack {
                    Text(UIStrings.patternColor).font(.callout)
                    Spacer()
                    BackdropColorWell(
                        model: model, title: UIStrings.patternColor, color: pattern.color,
                        actionName: EditorSession.patternColorActionName
                    ) { session, picked in session.setPatternColor(picked) }
                }
            }
            .disabled(pattern.kind == .none)
        }
    }
}

struct VignettePopover: View {
    let model: EditorModel

    private var vignette: Vignette { model.project.backdropSettings.effects.vignette }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EffectPopoverHeader(title: UIStrings.vignetteButton) { model.perform { $0.resetVignette() } }
            Picker(
                UIStrings.vignetteButton,
                selection: Binding(
                    get: { vignette.style }, set: { style in model.perform { $0.setVignetteStyle(style) } })
            ) {
                ForEach(VignetteStyle.allCases, id: \.self) { Text(UIStrings.vignetteName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(UIStrings.vignetteButton)
            .accessibilityValue(UIStrings.vignetteName(vignette.style))
            Group {
                EffectSlider(
                    model: model, title: UIStrings.effectSpread, value: vignette.spread, range: Vignette.range,
                    actionName: EditorSession.vignetteSpreadActionName
                ) { $0.setVignetteSpread($1) }
                EffectSlider(
                    model: model, title: UIStrings.effectIntensity, value: vignette.intensity, range: Vignette.range,
                    actionName: EditorSession.vignetteIntensityActionName
                ) { $0.setVignetteIntensity($1) }
            }
            .disabled(vignette.style == .none)
        }
    }
}

struct OverlayPopover: View {
    let model: EditorModel

    private var overlay: OverlayTexture { model.project.backdropSettings.effects.overlay }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EffectPopoverHeader(title: UIStrings.overlayButton) { model.perform { $0.resetOverlay() } }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(OverlayKind.allCases, id: \.self) { kind in
                    let selected = overlay.kind == kind
                    BackdropTile(
                        image: kind == .none ? nil : EffectThumbnails.shared.overlay(kind),
                        label: UIStrings.effectPickerItem(
                            UIStrings.overlayButton, UIStrings.overlayName(kind), selected: selected),
                        isSelected: selected
                    ) { model.perform { $0.setOverlayKind(kind) } }
                }
            }
            Group {
                EffectSlider(
                    model: model, title: UIStrings.effectOpacity, value: overlay.opacity,
                    range: OverlayTexture.opacityRange, actionName: EditorSession.overlayOpacityActionName
                ) { $0.setOverlayOpacity($1) }
                Picker(
                    UIStrings.overlayPosition,
                    selection: Binding(
                        get: { overlay.position }, set: { value in model.perform { $0.setOverlayPosition(value) } })
                ) {
                    ForEach(OverlayPosition.allCases, id: \.self) { Text(UIStrings.overlayPositionName($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(UIStrings.overlayPosition)
                .accessibilityValue(UIStrings.overlayPositionName(overlay.position))
            }
            .disabled(overlay.kind == .none)
        }
    }
}
