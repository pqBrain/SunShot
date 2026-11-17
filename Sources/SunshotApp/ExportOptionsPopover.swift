import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Format, size and a summary of what will be written; Copy and Export from here too.
struct ExportOptionsPopover: View {
    let model: EditorModel
    let dismiss: () -> Void
    @Environment(DocumentController.self) private var controller

    private var options: ExportOptions { model.exportOptions }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ControlCaption(UIStrings.formatPicker)
                Picker(UIStrings.formatPicker, selection: formatBinding) {
                    ForEach(model.availableFormats, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(UIStrings.formatPicker)
            }

            VStack(alignment: .leading, spacing: 6) {
                ControlCaption(UIStrings.scalePicker)
                Picker(UIStrings.scalePicker, selection: scaleBinding) {
                    ForEach(ExportScale.allCases, id: \.self) { scale in
                        Text(scale.displayName).tag(scale).accessibilityLabel(scale.spokenName)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!model.isScaleSelectable)
                .accessibilityLabel(UIStrings.scalePicker)
                if !model.isScaleSelectable {
                    Text(UIStrings.nativeSizeHint)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                SummaryRow(title: UIStrings.resolutionRow, value: model.resolutionText)
                Divider().opacity(0.5)
                SummaryRow(title: UIStrings.formatRow, value: model.formatText)
                Divider().opacity(0.5)
                SummaryRow(title: UIStrings.fileNameRow, value: model.suggestedExportName(), isFileName: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))

            if let problem = model.exportProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice = model.exportNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    dismiss()
                    Task { await model.copyPNG(to: .general) }
                } label: {
                    Label(UIStrings.copyPNG, systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .disabled(!model.canExport)
                .help(UIStrings.copyAccessibility)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                    Task { await DocumentFlows.export(controller) }
                } label: {
                    Text(UIStrings.exportNow)
                }
                .buttonStyle(.glassProminent)
                .disabled(!model.canExport)
                .accessibilityLabel(model.exportAccessibilityLabel)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var formatBinding: Binding<ExportFormat> {
        Binding(get: { options.format }, set: { format in model.perform { $0.setExportFormat(format) } })
    }

    private var scaleBinding: Binding<ExportScale> {
        Binding(get: { options.scale }, set: { scale in model.perform { $0.setExportScale(scale) } })
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String
    var isFileName = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            Spacer(minLength: 8)
            Text(value)
                .font(isFileName ? .caption.monospaced() : .callout.monospacedDigit())
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                .lineLimit(isFileName ? 2 : 1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
