import SunshotPlatform
import SwiftUI
import UniformTypeIdentifiers

/// Main window: translucent (desktop shows through), canvas in the middle, floating glass inspector on the right.
struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(DocumentController.self) private var controller
    @State private var isDropTargeted = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 0) {
            LayoutSidebar(model: model).frame(width: 168).padding([.top, .bottom, .leading], 12)
            canvasArea
            if model.showsInspector {
                InspectorView(model: model)
                    .fixedSize(horizontal: false, vertical: !model.isInspectorEnabled)
                    .frame(width: 292)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding([.top, .bottom, .trailing], 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: model.showsInspector)
        .task(id: colorScheme) { await model.setDarkAppearance(colorScheme == .dark)?.value }
        .task(id: model.animationFrameRequest) { if !model.animate.isPlaying { await model.renderAnimationFrame() } }
        .sheet(isPresented: Bindable(model.animate).showsExportSheet) { VideoExportSheet(model: model) }
        .containerBackground(.ultraThinMaterial, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .toolbar { EditorToolbar(model: model, controller: controller) }
        .templateGallery(model)
        .alert(
            model.alert?.title ?? "", isPresented: alertBinding, presenting: model.alert,
            actions: { _ in Button("OK") {} }, message: { Text($0.message) }
        )
        .modifier(CaptureSheets(model: model))
    }

    private var canvasArea: some View {
        VStack(spacing: 0) {
            previewArea
            if model.isSnippet { CodeEditorPanel(model: model) }
        }
    }

    private var previewArea: some View {
        ZStack {
            if let preview = model.displayedPreview, model.hasContent {
                CanvasPreview(image: preview, accessibilityLabel: model.previewAccessibilityLabel, model: model)
            } else {
                EmptyStateView(isTargeted: isDropTargeted) {
                    Task { await Panels.openImage(into: model) }
                } newSnippet: {
                    model.setContentKind(.code)
                }
            }
            if model.showsProgress {
                ProgressView(UIStrings.importing)
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: { size in
            // S6: render the preview at the size it can be shown (CanvasPreview's insets taken off).
            let insets = CanvasPreview.insets
            model.setPreviewDisplay(
                width: (size.width - insets.leading - insets.trailing) * displayScale,
                height: (size.height - insets.top - insets.bottom) * displayScale)
        }
        .overlay(alignment: .bottom) { NoticeBanner(model: model) }
        .overlay(alignment: .bottom) {
            if model.hasContent {
                if model.annotate.isActive {
                    AnnotationPalette(model: model).padding(.bottom, 16)
                } else if model.animate.isActive {
                    AnimateTimelineView(model: model)
                } else {
                    BottomToolbar(model: model)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.canAcceptDrop(urls) else { return false }
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

/// The rendered canvas, fitted to the space (S6: rendered at that size, so it fills the editor sharply). The
/// screenshot can be dragged, pinched and twisted in place; clicks reveal the matching inspector section.
struct CanvasPreview: View {
    /// Room around the canvas; the bottom leaves space for the floating Position / Crop bar.
    static let insets = EdgeInsets(top: 36, leading: 36, bottom: 76, trailing: 36)

    let image: CGImage
    let accessibilityLabel: String
    /// S5: inline title editing over the frame's title bar; the title is the preview's accessibility value.
    let model: EditorModel

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .overlay {
                if !model.annotate.isActive, !model.animate.isActive {
                    GeometryReader { CanvasInteractionLayer(model: model, size: $0.size) }
                }
            }
            .overlay { FrameTitleOverlay(model: model) }
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(model.previewAccessibilityValue)
            .accessibilityAddTraits(.isImage)
            .overlay { if model.annotate.isActive { AnnotationOverlay(model: model) } }
            .padding(Self.insets)
    }
}

struct EmptyStateView: View {
    let isTargeted: Bool
    let choose: () -> Void
    let newSnippet: () -> Void

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
            Button(UIStrings.newCodeSnippet, action: newSnippet)
                .buttonStyle(.glass)
                .accessibilityLabel(UIStrings.newCodeSnippetAccessibility)
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
