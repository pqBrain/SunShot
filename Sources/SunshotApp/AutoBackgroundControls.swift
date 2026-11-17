import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// S8: the Auto block: the content's palette strip, five generated backgrounds and Shuffle.
struct AutoBackgroundControls: View {
    let model: EditorModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        let state = AutoBackgroundStore.shared.state(for: model.session)
        let settings = model.project.backdropSettings
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ControlCaption(UIStrings.autoBackgrounds)
                Spacer()
                Button {
                    model.perform { $0.shuffleAutoBackgrounds() }
                } label: {
                    Label(UIStrings.autoShuffle, systemImage: "shuffle")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(state.palette.isEmpty)
                .accessibilityLabel(UIStrings.autoShuffleAccessibility)
            }
            if !state.palette.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(state.palette.enumerated()), id: \.offset) { _, color in
                        Rectangle().fill(Color(nsColor: color.nsColor))
                    }
                }
                .frame(height: 12)
                .clipShape(.capsule)
                .overlay { Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                .help(UIStrings.autoPalette)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(UIStrings.paletteAccessibility(state.palette))
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    let selected = settings.kind == .image && settings.image == .wallpaper(suggestion.wallpaper)
                    BackdropTile(
                        image: suggestion.thumbnail,
                        label: UIStrings.autoBackground(
                            index: index, count: state.suggestions.count, selected: selected),
                        isSelected: selected
                    ) { model.perform { $0.applyAutoBackground(suggestion.wallpaper) } }
                }
            }
        }
    }
}
