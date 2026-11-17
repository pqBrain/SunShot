import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

struct GradientControls: View {
    let model: EditorModel
    @State private var angleText = ""
    @State private var selectedStop = 0

    private var spec: GradientSpec { model.project.backdropSettings.gradient }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlCaption(UIStrings.gradientPresets)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(BackdropLibrary.shared.gradientPresets) { preset in
                    let selected = preset.spec == spec
                    BackdropTile(
                        image: BackdropLibrary.shared.thumbnail(for: preset),
                        label: UIStrings.gradientPreset(preset.name, selected: selected), isSelected: selected
                    ) {
                        selectedStop = 0
                        model.perform { $0.applyGradientPreset(preset.spec) }
                    }
                }
            }

            Picker(
                UIStrings.gradientKindName(spec.kind),
                selection: Binding(get: { spec.kind }, set: { kind in model.perform { $0.setGradientKind(kind) } })
            ) {
                ForEach(GradientKind.allCases, id: \.self) { Text(UIStrings.gradientKindName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Gradient type")
            .accessibilityValue(UIStrings.gradientKindName(spec.kind))

            angleRow.disabled(spec.kind == .radial).opacity(spec.kind == .radial ? 0.5 : 1)

            ControlCaption(UIStrings.gradientStops)
            GradientStopBar(model: model, selectedStop: $selectedStop)
            stopRow
        }
        .onAppear { angleText = UIStrings.angle(spec.angle) }
        .onChange(of: spec.angle) { _, value in angleText = UIStrings.angle(value) }
        .onChange(of: spec.stops.count) { _, count in selectedStop = min(selectedStop, count - 1) }
    }

    private var angleRow: some View {
        HStack(spacing: 10) {
            Text(UIStrings.gradientAngle)
                .font(.callout)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            Slider(
                value: Binding(
                    get: { spec.angle },
                    set: { value in model.perform { $0.setGradientAngle(value.rounded()) } }),
                in: 0...360
            ) {
                Text(UIStrings.gradientAngle)
            } onEditingChanged: { editing in
                editing ? model.beginGesture() : model.endGesture(EditorSession.gradientAngleActionName)
            }
            .labelsHidden()
            .accessibilityLabel(UIStrings.gradientAngleAccessibility)
            .accessibilityValue(UIStrings.angle(spec.angle))
            TextField(UIStrings.gradientAngle, text: $angleText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .onSubmit { if !model.setGradientAngle(text: angleText) { angleText = UIStrings.angle(spec.angle) } }
                .accessibilityLabel(UIStrings.gradientAngleAccessibility)
        }
    }

    private var stopRow: some View {
        let index = min(selectedStop, spec.stops.count - 1)
        return HStack(spacing: 10) {
            BackdropColorWell(
                model: model, title: UIStrings.stopColor, color: spec.stops[index].color,
                actionName: EditorSession.stopColorActionName
            ) { session, picked in session.setGradientStopColor(index, picked) }
            Text(spec.stops[index].color.hexString)
                .font(.callout.monospaced())
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            Spacer()
            Button {
                var added: Int?
                model.perform { added = $0.addGradientStop(at: spec.widestGapMidpoint) }
                if let added { selectedStop = added }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(!spec.canAddStop)
            .help(UIStrings.addStop)
            .accessibilityLabel(UIStrings.addStop)
            Button {
                var deleted = false
                model.perform { deleted = $0.deleteGradientStop(index) }
                if deleted { selectedStop = max(0, index - 1) }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(!spec.canDeleteStop)
            .help(UIStrings.deleteStop)
            .accessibilityLabel(UIStrings.deleteStop)
        }
    }
}

/// The gradient laid out left → right with a draggable handle per stop. Click the bar to add a stop; arrow keys
/// move the selected stop (0.01, ⇧ 0.1); Delete removes it (never below two stops).
struct GradientStopBar: View {
    let model: EditorModel
    @Binding var selectedStop: Int
    @FocusState private var isFocused: Bool
    @State private var draggingIndex: Int?

    private var spec: GradientSpec { model.project.backdropSettings.gradient }
    private let barHeight: CGFloat = 22
    private let handle: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - handle
            ZStack(alignment: .topLeading) {
                bar
                    .frame(width: width, height: barHeight)
                    .offset(x: handle / 2, y: 4)
                    .onTapGesture { location in
                        var added: Int?
                        let position = min(max(location.x / width, 0), 1)
                        model.perform { added = $0.addGradientStop(at: position) }
                        if let added { selectedStop = added }
                    }
                ForEach(Array(spec.stops.enumerated()), id: \.offset) { index, stop in
                    stopHandle(index: index, stop: stop)
                        .offset(x: stop.position * width, y: barHeight + 2)
                        .gesture(dragGesture(index: index, width: width))
                }
            }
        }
        .coordinateSpace(.named(GradientStopBar.space))
        .frame(height: barHeight + handle + 8)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .delete, .deleteForward]) { press in
            let index = min(selectedStop, spec.stops.count - 1)
            switch press.key {
            case .leftArrow, .rightArrow:
                let direction: Double = press.key == .leftArrow ? -1 : 1
                selectedStop = model.nudgeGradientStop(
                    index, direction: direction, large: press.modifiers.contains(.shift))
            default:
                var deleted = false
                model.perform { deleted = $0.deleteGradientStop(index) }
                if deleted { selectedStop = max(0, index - 1) }
            }
            return .handled
        }
        .help(UIStrings.stopBarHint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.gradientStops)
    }

    private var bar: some View {
        Group {
            if let image = BackdropLibrary.shared.stopBarImage(for: spec) {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: SunshotPalette.controlStroke).opacity(0.6), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func stopHandle(index: Int, stop: GradientStop) -> some View {
        let isSelected = index == selectedStop
        return Circle()
            .fill(Color(nsColor: stop.color.nsColor))
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .overlay {
                Circle().strokeBorder(
                    isSelected ? Color(nsColor: SunshotPalette.selectionRing) : .black.opacity(0.35),
                    lineWidth: isSelected ? 2 : 0.5
                )
                .padding(-2)
            }
            .shadow(color: .black.opacity(0.25), radius: draggingIndex == index ? 4 : 1.5, y: 1)
            .frame(width: handle, height: handle)
            .contentShape(.circle.inset(by: -4))
            .accessibilityElement()
            .accessibilityLabel(UIStrings.gradientStop(index: index, count: spec.stops.count, stop: stop))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAdjustableAction { direction in
                selectedStop = model.nudgeGradientStop(
                    index, direction: direction == .increment ? 1 : -1, large: false)
            }
    }

    private func dragGesture(index: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(GradientStopBar.space))
            .onChanged { value in
                if draggingIndex == nil {
                    draggingIndex = index
                    selectedStop = index
                    isFocused = true
                    model.beginGesture()
                }
                guard let current = draggingIndex else { return }
                let position = min(max((value.location.x - handle / 2) / width, 0), 1)
                var newIndex = current
                model.perform { newIndex = $0.moveGradientStop(current, to: position) }
                draggingIndex = newIndex
                selectedStop = newIndex
            }
            .onEnded { _ in
                draggingIndex = nil
                model.endGesture(EditorSession.moveStopActionName)
            }
    }

    static let space = "gradient-stop-bar"
}
