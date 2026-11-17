import SunshotCore
import SunshotPlatform
import SwiftUI

/// Screenshots section (S15): the screenshot layout picker and one row per slot of the active arrangement (a
/// screenshot layout or a multi-device layout). A row takes an image from the open panel or a drop.
struct ScreenshotsControls: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ControlCaption(UIStrings.screenshotLayout)
                Picker(
                    UIStrings.screenshotLayout,
                    selection: Binding(get: { model.collage?.id }, set: { model.setCollage($0) })
                ) {
                    Text(UIStrings.screenshotLayoutNone).tag(String?.none)
                    ForEach(model.collageCatalog.arrangements) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .disabled(model.device != nil)
                .accessibilityLabel(UIStrings.screenshotLayout)
            }
            let rows = model.screenshotRows
            if rows.count > 1 {
                ForEach(rows) { row in
                    ScreenshotRowView(model: model, row: row)
                }
            }
            Text(UIStrings.screenshotsHint(hasDevice: model.device != nil, multiple: rows.count > 1))
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.smooth(duration: 0.2), value: rows.map(\.id))
    }

    private var rows: [ScreenshotRow] { model.screenshotRows }
}

private struct ScreenshotRowView: View {
    let model: EditorModel
    let row: ScreenshotRow
    @State private var isTargeted = false

    private var shown: CGImage? { row.image ?? model.mainImage }

    private var hasImage: Bool { row.slot.isPrimary || row.image != nil }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .opacity(hasImage ? 1 : 0.3)
                .accessibilityHidden(true)
            Group {
                if let shown {
                    Image(decorative: shown, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.08)
                }
            }
            .frame(width: 44, height: 30)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
            .opacity(hasImage ? 1 : 0.45)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : .white.opacity(0.12), lineWidth: isTargeted ? 2 : 1)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                if !hasImage {
                    Text(UIStrings.screenshotSameAsMain)
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .lineLimit(1)
                }
            }
            .layoutPriority(-1)
            Spacer(minLength: 0)
            if !row.slot.isPrimary {
                Button {
                    Task { await Panels.chooseSlotImage(for: model, number: row.slot.number) }
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(UIStrings.screenshotChoose)
                .accessibilityLabel(UIStrings.screenshotChooseAccessibility(row.name))
            }
            if model.canRemoveScreenshot(row.slot.number) {
                Button {
                    model.removeScreenshot(at: row.slot.number)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(UIStrings.screenshotRemove)
                .accessibilityLabel(UIStrings.screenshotRemoveAccessibility(row.name))
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .draggable(ScreenshotDrag.payload(number: row.slot.number)) {
            if let shown {
                Image(decorative: shown, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(width: 88)
            }
        }
        .dropDestination(for: ScreenshotDrop.self) { items, _ in
            guard let item = items.first else { return false }
            switch item {
            case .screenshot(let number):
                guard number != row.slot.number else { return false }
                model.moveScreenshot(from: number, to: row.slot.number)
                return true
            case .file(let url):
                guard !row.slot.isPrimary, isSupportedImageFile(url) else { return false }
                Task { await model.importDroppedSlot([url], number: row.slot.number) }
                return true
            }
        } isTargeted: {
            isTargeted = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.screenshotRow(row.name, hasImage: hasImage))
        .accessibilityHint(UIStrings.screenshotDragHint)
    }
}

/// What can be dropped on a Screenshots row: another row (swap places) or an image file (fill that screenshot).
enum ScreenshotDrop: Transferable {
    case screenshot(Int)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in ScreenshotDrop.file(url) })
        ProxyRepresentation(importing: { (text: String) in
            guard let number = ScreenshotDrag.number(from: text) else { throw ScreenshotDropError.unknown }
            return ScreenshotDrop.screenshot(number)
        })
    }
}

enum ScreenshotDropError: Error { case unknown }
