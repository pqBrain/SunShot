import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Device section (S12): None plus one tile per device (live thumbnails), finish swatches, orientation,
/// multi-device layout, the recommended media size and the suggestion for the imported image.
struct DeviceControls: View {
    let model: EditorModel
    @Environment(DocumentController.self) private var controller
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let suggestion = model.deviceSuggestion(enabled: controller.settings.suggestDevice) {
                SuggestionRow(suggestion: suggestion) { model.applyDeviceSuggestion(suggestion) }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                DeviceTile(name: UIStrings.deviceNone, image: nil, isSelected: model.device == nil) {
                    model.setDevice(nil)
                }
                ForEach(model.deviceModels) { device in
                    DeviceTile(
                        name: device.name, image: model.deviceThumbnail(device),
                        isSelected: model.device?.model == device.id
                    ) { model.setDevice(device.id) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(UIStrings.deviceSection)

            if let device = model.device {
                FinishRow(model: model, selected: device.finish)
                if model.canTurnDevice {
                    HStack(spacing: 10) {
                        ControlCaption(UIStrings.deviceOrientation)
                        Picker(
                            UIStrings.deviceOrientation,
                            selection: Binding(get: { device.landscape }, set: { model.setDeviceLandscape($0) })
                        ) {
                            Text(UIStrings.devicePortrait).tag(false)
                            Text(UIStrings.deviceLandscape).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel(UIStrings.deviceOrientation)
                    }
                }
                HStack(spacing: 10) {
                    ControlCaption(UIStrings.deviceArrangement)
                    Picker(
                        UIStrings.deviceArrangement,
                        selection: Binding(get: { device.arrangement }, set: { model.setDeviceArrangement($0) })
                    ) {
                        ForEach(model.deviceArrangements) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .accessibilityLabel(UIStrings.deviceArrangement)
                }
                if let size = model.recommendedMediaSize {
                    Text(UIStrings.recommendedMedia(size))
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: model.device)
    }
}

private struct SuggestionRow: View {
    let suggestion: DeviceSuggestion
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.tint).accessibilityHidden(true)
            Text(UIStrings.deviceSuggestion(suggestion))
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(UIStrings.deviceSuggestionUse, action: apply)
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel("\(UIStrings.deviceSuggestionUse): \(UIStrings.deviceSuggestion(suggestion))")
        }
        .padding(10)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct FinishRow: View {
    let model: EditorModel
    let selected: String

    var body: some View {
        HStack(spacing: 10) {
            ControlCaption(UIStrings.deviceFinish)
            ForEach(model.deviceFinishes) { finish in
                let isSelected = finish.id == selected
                Button {
                    model.setDeviceFinish(finish.id)
                } label: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(rgba: finish.highlight), Color(rgba: finish.shell)], startPoint: .top,
                                endPoint: .bottom)
                        )
                        .overlay { Circle().strokeBorder(Color(rgba: finish.edge), lineWidth: 1) }
                        .frame(width: 22, height: 22)
                        .padding(2)
                        .overlay {
                            Circle().strokeBorder(
                                isSelected ? Color(nsColor: SunshotPalette.selectionRing) : .clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help(finish.name)
                .accessibilityLabel(UIStrings.finishOption(finish.name, selected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

private struct DeviceTile: View {
    let name: String
    let image: CGImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "nosign")
                            .font(.title3)
                            .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    }
                }
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .padding(4)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color(nsColor: SunshotPalette.selectionRing) : .clear, lineWidth: 2)
                }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UIStrings.deviceOption(name, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    /// An sRGB finish colour as a SwiftUI colour.
    fileprivate init(rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
