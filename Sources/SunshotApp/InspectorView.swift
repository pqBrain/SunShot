import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Floating glass panel with the style controls.
struct InspectorView: View {
    @Bindable var model: EditorModel
    @State private var borderExpanded = true
    @State private var shadowExpanded = true
    @State private var backdropExpanded = true
    @State private var canvasExpanded = true
    @State private var frameExpanded = true
    @State private var deviceExpanded = true
    @State private var colorsExpanded = false
    @State private var codeExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.isInspectorEnabled {
                    ThemeHeaderView()
                    if model.isSnippet {
                        InspectorSection(
                            title: UIStrings.codeSection, isExpanded: $codeExpanded,
                            reset: { model.perform { $0.resetCodeStyle() } }
                        ) { CodeSnippetControls(model: model) }
                    }
                    InspectorSection(
                        title: UIStrings.canvasSection, isExpanded: $canvasExpanded,
                        reset: { model.perform { $0.resetCanvas() } }
                    ) { CanvasSizeControls(model: model) }
                    InspectorSection(
                        title: UIStrings.backdropSection, isExpanded: $backdropExpanded,
                        reset: { model.perform { $0.resetBackdrop() } }
                    ) { BackdropControls(model: model) }
                    InspectorSection(
                        title: UIStrings.borderSection, isExpanded: $borderExpanded,
                        reset: { model.perform { $0.resetBorder() } }
                    ) { BorderControls(model: model) }
                    InspectorSection(
                        title: UIStrings.shadowSection, isExpanded: $shadowExpanded,
                        reset: { model.perform { $0.resetShadow() } }
                    ) { ShadowControls(model: model) }
                    InspectorSection(
                        title: UIStrings.frameSection, isExpanded: $frameExpanded,
                        reset: { model.perform { $0.resetFrame() } }
                    ) { FrameControls(model: model) }
                    InspectorSection(
                        title: UIStrings.deviceSection, isExpanded: $deviceExpanded,
                        reset: { model.setDevice(nil) }
                    ) { DeviceControls(model: model) }
                    InspectorSection(
                        title: UIStrings.colorsSection, isExpanded: $colorsExpanded,
                        reset: { model.perform { $0.resetColors() } }
                    ) { ColorTokenControls(model: model) }
                } else {
                    Text(UIStrings.inspectorEmpty)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.never)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.inspector)
    }
}

/// Collapsible section with a per-section Reset button.
struct InspectorSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let reset: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(title, systemImage: "chevron.right")
                        .labelStyle(SectionHeaderLabelStyle(isExpanded: isExpanded))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "expanded" : "collapsed")
                Spacer()
                Button(UIStrings.reset, action: reset)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel(UIStrings.resetSection(title))
            }
            if isExpanded {
                content.transition(.opacity)
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 16, style: .continuous))
        .animation(.smooth(duration: 0.2), value: isExpanded)
    }
}

struct SectionHeaderLabelStyle: LabelStyle {
    let isExpanded: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.caption.weight(.bold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            configuration.title
                .font(.headline)
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
        }
        .contentShape(.rect)
    }
}

struct BorderControls: View {
    let model: EditorModel
    @State private var radiusText = ""

    private var border: Border { model.project.border }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                "Corners",
                selection: Binding(get: { border.style }, set: { style in model.perform { $0.setCornerStyle(style) } })
            ) {
                ForEach(CornerStyle.allCases, id: \.self) { Text(UIStrings.cornerStyleName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(UIStrings.cornerStyle(border.style))

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { border.radius }, set: { value in model.perform { $0.setCornerRadius(value.rounded()) } }),
                    in: Border.radiusRange
                ) {
                    Text("Radius")
                } onEditingChanged: { editing in
                    editing ? model.beginGesture() : model.endGesture(EditorSession.cornerRadiusActionName)
                }
                .labelsHidden()
                .accessibilityLabel(UIStrings.cornerRadius(border.radius))

                TextField("Radius", text: $radiusText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .onSubmit {
                        if !model.setCornerRadius(text: radiusText) { radiusText = Self.format(border.radius) }
                    }
                    .accessibilityLabel(UIStrings.cornerRadius(border.radius))
                Text("px").font(.callout).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            .disabled(border.style == .sharp)
        }
        .onAppear { radiusText = Self.format(border.radius) }
        .onChange(of: border.radius) { _, value in radiusText = Self.format(value) }
    }

    static func format(_ value: Double) -> String { String(Int(value.rounded())) }
}

struct ShadowControls: View {
    let model: EditorModel

    private var shadow: Shadow { model.project.shadow }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                "Style",
                selection: Binding(get: { shadow.style }, set: { style in model.perform { $0.setShadowStyle(style) } })
            ) {
                ForEach(ShadowStyle.allCases, id: \.self) { Text(UIStrings.shadowStyleName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(UIStrings.shadowStyle(shadow.style))

            Picker(
                "Intensity",
                selection: Binding(
                    get: { shadow.intensity }, set: { value in model.perform { $0.setShadowIntensity(value) } })
            ) {
                ForEach(ShadowIntensity.allCases, id: \.self) { Text(UIStrings.intensityName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(UIStrings.shadowIntensity(shadow.intensity))

            HStack {
                Spacer()
                LightSourcePad(model: model)
                    .disabled(shadow.style == .none)
                    .opacity(shadow.style == .none ? 0.4 : 1)
                Spacer()
            }
        }
    }
}
