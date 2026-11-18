import SunshotPlatform
import SwiftUI

/// S7: a short toolbar — Add image, Capture, Annotate, Animate, Export and the inspector. Clear Content (⌘⌫),
/// Start Over (File menu) and Copy (⌘C) live in the menu bar; Copy PNG and Export Options are in Export's menu;
/// layouts and templates are in the left sidebar.
struct EditorToolbar: ToolbarContent {
    let model: EditorModel
    let controller: DocumentController

    var body: some ToolbarContent {
        // S16: one switch between the screenshot and the code snippet; each side is kept while the other shows.
        // S17-AC2: centred in the toolbar.
        ToolbarItem(placement: .principal) {
            ContentKindPicker(model: model)
        }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await Panels.openImage(into: model) }
            } label: {
                Label(UIStrings.chooseImage, systemImage: "photo.badge.plus")
            }
            .help(UIStrings.chooseImageAccessibility)
            .accessibilityLabel(UIStrings.chooseImageAccessibility)

            CaptureToolbarMenu(controller: controller)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            // S17-AC3: shows or hides the annotation bar (shown by default).
            Button {
                model.toggleAnnotationBar()
            } label: {
                Label(UIStrings.annotate, systemImage: "pencil.tip.crop.circle")
            }
            .help(model.annotationBarToggleTitle)
            .accessibilityLabel(model.annotationBarToggleTitle)
            .disabled(!model.canToggleAnnotationBar)
            Button {
                model.toggleAnimateMode()
            } label: {
                Label(UIStrings.animate, systemImage: "film.stack")
            }
            .help(UIStrings.animateAccessibility)
            .accessibilityLabel(UIStrings.animateAccessibility)
            .disabled(!model.canAnimate)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ExportMenuButton(model: model, controller: controller)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showsInspector.toggle()
            } label: {
                Label(UIStrings.inspector, systemImage: "sidebar.trailing")
            }
            .help(UIStrings.toggleInspector)
            .accessibilityLabel(UIStrings.toggleInspector)
        }
    }
}

/// Export as a split button: a click exports as before; its menu copies the PNG or opens the export options
/// popover (format, size, file name). While the options make export impossible, a click opens them instead.
struct ExportMenuButton: View {
    let model: EditorModel
    let controller: DocumentController
    @State private var showsOptions = false

    var body: some View {
        Menu {
            Button(UIStrings.copyPNG) { Task { await model.copyPNG(to: .general) } }
                .accessibilityLabel(UIStrings.copyAccessibility)
            Button(UIStrings.exportOptionsMenu) { showsOptions = true }
                .accessibilityLabel(UIStrings.exportOptionsAccessibility)
            Divider()
            Button(UIStrings.saveDefaultStyle) { controller.saveQuickStyle() }
                .accessibilityLabel(UIStrings.saveDefaultStyleAccessibility)
        } label: {
            Label(model.exportButtonTitle, systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
        } primaryAction: {
            if model.canExport {
                Task { await DocumentFlows.export(controller) }
            } else {
                showsOptions = true
            }
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .help(model.exportAccessibilityLabel)
        .accessibilityLabel(model.exportAccessibilityLabel)
        .accessibilityHint(UIStrings.exportMenuAccessibility)
        .disabled(!model.hasContent)
        .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
            ExportOptionsPopover(model: model) { showsOptions = false }
        }
    }
}

/// S16: Screenshot | Code. Switching keeps the other side, so coming back shows it as it was (one undo step each).
struct ContentKindPicker: View {
    let model: EditorModel

    var body: some View {
        Picker(UIStrings.contentKindAccessibility, selection: kind) {
            ForEach(ContentKind.allCases, id: \.self) { kind in
                Label(
                    UIStrings.contentKindName(kind),
                    systemImage: kind == .screenshot ? "photo" : "chevron.left.forwardslash.chevron.right"
                )
                .labelStyle(.titleAndIcon)
                .help(UIStrings.contentKindHelp(kind))
                .tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(UIStrings.contentKindAccessibility)
    }

    private var kind: Binding<ContentKind> {
        Binding(get: { model.contentKind }, set: { model.setContentKind($0) })
    }
}
