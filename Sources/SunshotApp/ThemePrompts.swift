import AppKit
import SunshotCore
import SunshotPlatform

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
