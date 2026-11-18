import SunshotCore
import SunshotPlatform
import SwiftUI

/// Sidebar ▸ Templates: the template gallery in one column, previewed with the current content. Choosing one
/// restyles the document as one undo step; "Show all templates…" opens the full gallery sheet.
struct SidebarTemplates: View {
    let model: EditorModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SidebarHint(model.hasContent ? UIStrings.templatesHint : UIStrings.templatesSample)
                ForEach(model.templates.templates) { template in
                    TemplateCard(
                        template: template, image: model.templates.thumbnails[template.id],
                        isCurrent: model.hasContent && model.isCurrentTemplate(template), previewHeight: 84
                    ) { model.applyTemplate(template) }
                    .padding(.horizontal, 10)
                }
                Button(UIStrings.templatesShowAll) { model.showTemplateGallery() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
        .scrollContentBackground(.hidden)
        .task { model.scheduleTemplateThumbnails() }
    }
}
