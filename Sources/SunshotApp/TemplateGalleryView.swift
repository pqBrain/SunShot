import SunshotCore
import SunshotPlatform
import SwiftUI

/// File ▸ Templates… (⇧⌘T) and the sidebar's "Show all templates…": a sheet of Sunshot's templates, each previewed live
/// with the current content by the shared renderer. Choosing one restyles the document as one undo step.
struct TemplateGalleryView: View {
    let model: EditorModel
    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 14)]

    private var screens: [DocumentTemplate] { model.templates.templates.filter { !$0.usesDevice } }
    private var devices: [DocumentTemplate] { model.templates.templates.filter(\.usesDevice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(UIStrings.templatesTitle).font(.title2.weight(.semibold))
                Spacer()
                Button(UIStrings.close) { model.templates.isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            Text(model.hasContent ? UIStrings.templatesHint : UIStrings.templatesSample)
                .font(.callout)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group(UIStrings.templatesScreens, screens)
                    group(UIStrings.templatesDevices, devices)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .task { model.scheduleTemplateThumbnails() }
    }

    @ViewBuilder
    private func group(_ title: String, _ templates: [DocumentTemplate]) -> some View {
        if !templates.isEmpty {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(templates) { template in
                    TemplateCard(
                        template: template, image: model.templates.thumbnails[template.id],
                        isCurrent: model.hasContent && model.isCurrentTemplate(template)
                    ) { model.applyTemplate(template) }
                }
            }
        }
    }
}

/// One template, previewed with the current content (gallery sheet and the sidebar's Templates pane).
struct TemplateCard: View {
    let template: DocumentTemplate
    let image: CGImage?
    let isCurrent: Bool
    var previewHeight: CGFloat = 112
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: previewHeight)
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? Color(nsColor: SunshotPalette.selectionRing) : .clear, lineWidth: 2)
                }
                Text(template.name).font(.callout.weight(.medium))
                Text(template.summary)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(template.summary)
        .accessibilityLabel(UIStrings.templateOption(template, current: isCurrent))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

extension View {
    /// Presents the template gallery while `model.templates.isPresented`.
    func templateGallery(_ model: EditorModel) -> some View {
        sheet(
            isPresented: Binding(get: { model.templates.isPresented }, set: { model.templates.isPresented = $0 })
        ) { TemplateGalleryView(model: model) }
    }
}
