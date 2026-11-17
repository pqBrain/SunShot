import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Left sidebar: layout presets as live thumbnails of the current image and style. Click or Return applies;
/// the applied layout has an accent outline. Disabled with placeholders while there's no content.
struct LayoutSidebar: View {
    let model: EditorModel
    /// Keyboard cursor (arrow keys move it; Return applies it).
    @State private var cursor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.layoutsTitle)
                .font(.headline)
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                .padding(.horizontal, 14)
                .padding(.top, 14)
            if !model.hasContent {
                Text(UIStrings.layoutsEmpty)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    .padding(.horizontal, 14)
            }
            List(model.layout.presets, selection: $cursor) { preset in
                LayoutRow(
                    preset: preset, thumbnail: model.layout.thumbnails[preset.id],
                    isApplied: model.session.layoutPresetID == preset.id
                )
                .contentShape(.rect)
                .onTapGesture { apply(preset) }
                .tag(preset.id)
                .listRowSeparator(.hidden)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onKeyPress(.return) {
                guard let preset = model.layout.presets.first(where: { $0.id == cursor }) else { return .ignored }
                apply(preset)
                return .handled
            }
            .disabled(!model.hasContent)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.layoutsTitle)
    }

    private func apply(_ preset: LayoutPreset) {
        guard model.hasContent else { return }
        cursor = preset.id
        model.applyLayoutPreset(preset)
    }
}

struct LayoutRow: View {
    let preset: LayoutPreset
    let thumbnail: CGImage?
    let isApplied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.08))
                        .aspectRatio(1.5, contentMode: .fit)
                }
            }
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isApplied ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            Text(preset.name)
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UIStrings.layout(preset.name, selected: isApplied))
        .accessibilityAddTraits(isApplied ? [.isButton, .isSelected] : .isButton)
    }
}
