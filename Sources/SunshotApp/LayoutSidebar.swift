import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Left sidebar: one picker for Layouts and Templates (S7; S17 dropped Themes), so the toolbar and inspector stay
/// short. The picker is centred (S17-AC2).
struct LayoutSidebar: View {
    let model: EditorModel
    @State private var pane: SidebarPane = .layouts

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(UIStrings.sidebarPickerAccessibility, selection: $pane) {
                ForEach(SidebarPane.allCases) { pane in
                    Image(systemName: Self.symbol(pane))
                        .help(pane.title)
                        .accessibilityLabel(pane.title)
                        .tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            Text(pane.title)
                .font(.headline)
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                .padding(.horizontal, 14)
                .accessibilityAddTraits(.isHeader)
            switch pane {
            case .layouts: LayoutList(model: model)
            case .templates: SidebarTemplates(model: model)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pane.title)
    }

    private static func symbol(_ pane: SidebarPane) -> String {
        switch pane {
        case .layouts: "rectangle.3.group"
        case .templates: "square.grid.2x2"
        }
    }
}

/// Layout presets as live thumbnails of the current image and style. Click or Return applies; the applied layout
/// has an accent outline. Before there is an image only a hint is shown.
private struct LayoutList: View {
    let model: EditorModel
    /// Keyboard cursor (arrow keys move it; Return applies it).
    @State private var cursor: String?

    var body: some View {
        if model.hasContent {
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
        } else {
            SidebarHint(UIStrings.layoutsEmpty)
        }
    }

    private func apply(_ preset: LayoutPreset) {
        guard model.hasContent else { return }
        cursor = preset.id
        model.applyLayoutPreset(preset)
    }
}

/// Secondary-text caption used for the sidebar's empty states.
struct SidebarHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
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
