import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: SunshotPalette.workspaceBackground).ignoresSafeArea()
            if let preview = model.preview, model.hasContent {
                CanvasPreview(image: preview, accessibilityLabel: model.previewAccessibilityLabel)
            } else {
                EmptyStateView(isTargeted: isDropTargeted) { Task { await Panels.openImage(into: model) } }
            }
            if model.showsProgress {
                ProgressView(UIStrings.importing).padding().background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
        }
        .overlay(alignment: .bottom) { NoticeBanner(model: model) }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.contains(where: isSupportedImageFile) else { return false }
            Task { await model.importDroppedFiles(urls) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .toolbar { EditorToolbar(model: model) }
        .alert(
            model.alert?.title ?? "", isPresented: alertBinding, presenting: model.alert,
            actions: { _ in Button("OK") {} }, message: { Text($0.message) })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

/// Shows the rendered canvas, fitted to the window, never larger than 1 image pixel per screen pixel.
struct CanvasPreview: View {
    let image: CGImage
    let accessibilityLabel: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(decorative: image, scale: displayScale)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(
                maxWidth: CGFloat(image.width) / displayScale, maxHeight: CGFloat(image.height) / displayScale
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(32)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }
}

struct EmptyStateView: View {
    let isTargeted: Bool
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .accessibilityHidden(true)
            Text(UIStrings.dropTitle)
                .font(.title2.weight(.medium))
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
            Button(UIStrings.chooseImage, action: choose)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(UIStrings.chooseImageAccessibility)
            Text(UIStrings.pasteHint)
                .font(.callout)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
        }
        .padding(48)
        .frame(maxWidth: 460, maxHeight: 320)
        .background(Color(nsColor: SunshotPalette.dropZoneFill), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color(nsColor: isTargeted ? SunshotPalette.dropZoneHighlight : SunshotPalette.dropZoneStroke),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: [7, 5]))
        }
        .padding(40)
    }
}

struct EditorToolbar: ToolbarContent {
    let model: EditorModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await Panels.openImage(into: model) }
            } label: {
                Label(UIStrings.chooseImage, systemImage: "photo.badge.plus")
            }
            .help(UIStrings.chooseImageAccessibility)
            .accessibilityLabel(UIStrings.chooseImageAccessibility)

            Button {
                Task { await model.clearContent() }
            } label: {
                Label(UIStrings.clearContent, systemImage: "trash")
            }
            .help(UIStrings.clearAccessibility)
            .accessibilityLabel(UIStrings.clearAccessibility)
            .disabled(!model.hasContent)

            Button {
                Task { await model.copyPNG(to: .general) }
            } label: {
                Label(UIStrings.copyPNG, systemImage: "doc.on.doc")
            }
            .help(UIStrings.copyAccessibility)
            .accessibilityLabel(UIStrings.copyAccessibility)
            .disabled(!model.hasContent)

            Button {
                Task { await Panels.exportPNG(from: model) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help(UIStrings.exportAccessibility)
            .accessibilityLabel(UIStrings.exportAccessibility)
            .disabled(!model.hasContent)
        }
    }
}

/// Short-lived message at the bottom of the window (e.g. several files dropped).
struct NoticeBanner: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let notice = model.notice {
            Text(notice)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 16)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    if model.notice == notice { model.notice = nil }
                }
        }
    }
}
