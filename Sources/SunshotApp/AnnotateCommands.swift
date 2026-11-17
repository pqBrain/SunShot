import SunshotCore
import SunshotPlatform
import SwiftUI

/// Annotate menu. Single-letter tool keys are handled by the annotation canvas (so they never steal typing from
/// text fields); the menu lists them in each title and binds only shortcuts that use ⌘.
struct AnnotateCommands: Commands {
    let model: EditorModel

    var body: some Commands {
        CommandMenu(UIStrings.annotate) {
            Button(model.annotate.isActive ? UIStrings.doneAnnotating : UIStrings.annotate) {
                model.toggleAnnotateMode()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!model.canAnnotate)
            Divider()
            ForEach(AnnotationTool.allCases.filter { $0 != .sticker }, id: \.self) { tool in
                Button(UIStrings.toolLabel(tool)) { model.selectTool(tool) }
                    .disabled(!model.annotate.isActive)
            }
            Button(UIStrings.stickers) { model.annotate.showsStickerPicker = true }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!model.annotate.isActive)
            Divider()
            Button(UIStrings.duplicate) { model.duplicateSelectedAnnotations() }
                .keyboardShortcut("d")
                .disabled(!model.annotate.isActive || model.annotationSelection.isEmpty)
            Button(UIStrings.deleteSelection) { model.deleteSelectedAnnotations() }
                .disabled(!model.annotate.isActive || model.annotationSelection.isEmpty)
            Button(UIStrings.clearAnnotations) { model.clearAnnotations() }
                .disabled(!model.hasAnnotations)
        }
    }
}
