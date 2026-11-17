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

/// Sidebar ▸ Themes: the applied theme, the saved themes (click applies; right-click renames, duplicates or
/// deletes) and "Save current style as theme". Replaces the inspector's theme menu.
struct SidebarThemes: View {
    let model: EditorModel
    @Environment(DocumentController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.themeHeaderTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .accessibilityLabel(UIStrings.themeAccessibility(controller.themeHeaderTitle))
            if controller.themes.isEmpty {
                SidebarHint(UIStrings.themesEmpty)
            }
            List(controller.themes) { theme in
                ThemeRow(theme: theme, isApplied: controller.appliedTheme?.id == theme.id) {
                    controller.applyTheme(theme)
                }
                .disabled(!model.hasContent)
                .contextMenu {
                    Button(UIStrings.rename) { ThemePrompts.rename(theme, in: controller) }
                    Button(UIStrings.duplicate) { _ = try? controller.duplicateTheme(id: theme.id) }
                    Button(UIStrings.delete, role: .destructive) { try? controller.deleteTheme(id: theme.id) }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Button(UIStrings.saveCurrentTheme) { ThemePrompts.save(in: controller) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!model.hasContent)
                .accessibilityLabel(UIStrings.saveThemeAccessibility)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
    }
}

private struct ThemeRow: View {
    let theme: Theme
    let isApplied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(theme.name).lineLimit(1)
                Spacer()
                if isApplied { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UIStrings.themeRow(theme.name, applied: isApplied))
        .accessibilityAddTraits(isApplied ? [.isButton, .isSelected] : .isButton)
    }
}
