import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

/// Main window: translucent (desktop shows through), canvas in the middle, floating glass inspector on the right.
struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            canvasArea
            if model.showsInspector {
                InspectorView(model: model)
                    .frame(width: 292)
                    .padding([.top, .bottom, .trailing], 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: model.showsInspector)
        .containerBackground(.ultraThinMaterial, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .toolbar { EditorToolbar(model: model) }
        .alert(
            model.alert?.title ?? "", isPresented: alertBinding, presenting: model.alert,
            actions: { _ in Button("OK") {} }, message: { Text($0.message) })
    }

    private var canvasArea: some View {
        ZStack {
            if let preview = model.preview, model.hasContent {
                CanvasPreview(image: preview, accessibilityLabel: model.previewAccessibilityLabel)
            } else {
                EmptyStateView(isTargeted: isDropTargeted) { Task { await Panels.openImage(into: model) } }
            }
            if model.showsProgress {
                ProgressView(UIStrings.importing)
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { NoticeBanner(model: model) }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.contains(where: isSupportedImageFile) else { return false }
            Task { await model.importDroppedFiles(urls) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

/// The rendered canvas, fitted to the space, never larger than 1 image pixel per screen pixel.
struct CanvasPreview: View {
    let image: CGImage
    let accessibilityLabel: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(decorative: image, scale: displayScale)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: CGFloat(image.width) / displayScale, maxHeight: CGFloat(image.height) / displayScale)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .padding(36)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isImage)
    }
}

struct EmptyStateView: View {
    let isTargeted: Bool
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52, weight: .thin))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isTargeted ? Color.accentColor : Color(nsColor: SunshotPalette.secondaryText))
                .accessibilityHidden(true)
            Text(UIStrings.dropTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
            Button(UIStrings.chooseImage, action: choose)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(UIStrings.chooseImageAccessibility)
            Text(UIStrings.pasteHint)
                .font(.callout)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 44)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1, dash: isTargeted ? [] : [8, 6]))
        }
        .scaleEffect(isTargeted ? 1.03 : 1)
        .animation(.smooth(duration: 0.2), value: isTargeted)
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
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await Panels.exportPNG(from: model) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glassProminent)
            .help(UIStrings.exportAccessibility)
            .accessibilityLabel(UIStrings.exportAccessibility)
            .disabled(!model.hasContent)
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

/// Short-lived message at the bottom of the window (e.g. several files dropped).
struct NoticeBanner: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let notice = model.notice {
            Text(notice)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    if model.notice == notice { model.notice = nil }
                }
        }
    }
}
