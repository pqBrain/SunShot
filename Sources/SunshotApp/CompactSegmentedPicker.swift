import SunshotPlatform
import SwiftUI

/// A segmented choice that always fits its column: equal-width segments that share the space offered (the system
/// segmented control keeps its own intrinsic width, and four labels overflow the 240 pt inspector column; S17).
struct CompactSegmentedPicker<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? Color.white : Color(nsColor: SunshotPalette.primaryText))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.accentColor : .clear))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
