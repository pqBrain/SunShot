import AppKit
import SunshotCore
import SunshotPlatform
import SwiftUI

/// Inspector header: the applied theme ("No Theme", "Ocean", "Ocean (modified)"), a menu to apply or manage
/// saved themes, and Save.
struct ThemeHeaderView: View {
    @Environment(DocumentController.self) private var controller

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if controller.themes.isEmpty {
                    Text(UIStrings.noSavedThemes)
                }
                ForEach(controller.themes) { theme in
                    Button(theme.name) { controller.applyTheme(theme) }
                }
                if !controller.themes.isEmpty {
                    Divider()
                    Menu(UIStrings.manageThemes) {
                        ForEach(controller.themes) { theme in
                            Menu(theme.name) {
                                Button(UIStrings.rename) { ThemePrompts.rename(theme, in: controller) }
                                Button(UIStrings.duplicate) { _ = try? controller.duplicateTheme(id: theme.id) }
                                Button(UIStrings.delete, role: .destructive) {
                                    try? controller.deleteTheme(id: theme.id)
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(controller.themeHeaderTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(UIStrings.themeAccessibility(controller.themeHeaderTitle))
            Spacer()
            Button(UIStrings.saveTheme) { ThemePrompts.save(in: controller) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel(UIStrings.saveThemeAccessibility)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// Name prompts for Save and Rename (NSAlert with a text field: Return confirms, Esc cancels).
@MainActor
enum ThemePrompts {
    static func save(in controller: DocumentController) {
        guard let name = ask(title: UIStrings.saveThemeTitle, initial: "", confirm: UIStrings.save) else { return }
        do {
            try controller.saveTheme(named: name)
        } catch ThemeName.Problem.duplicate {
            let alert = NSAlert()
            alert.messageText = ThemeName.Problem.duplicate(existingID: "").message
            alert.addButton(withTitle: UIStrings.replace).hasDestructiveAction = true
            alert.addButton(withTitle: UIStrings.cancel)
            if alert.runModal() == .alertFirstButtonReturn {
                _ = try? controller.saveTheme(named: name, replacing: true)
            }
        } catch let problem as ThemeName.Problem {
            show(problem.message)
        } catch {
            show(error.localizedDescription)
        }
    }

    static func rename(_ theme: Theme, in controller: DocumentController) {
        guard let name = ask(title: UIStrings.renameThemeTitle, initial: theme.name, confirm: UIStrings.save) else {
            return
        }
        do {
            try controller.renameTheme(id: theme.id, to: name)
        } catch let problem as ThemeName.Problem {
            show(problem.message)
        } catch {
            show(error.localizedDescription)
        }
    }

    private static func ask(title: String, initial: String, confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        field.placeholderString = UIStrings.themeNamePrompt
        field.setAccessibilityLabel(UIStrings.themeNamePrompt)
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: UIStrings.cancel)
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private static func show(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
