import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Canvas section: one glass button showing the current size; it opens the size picker popover.
struct CanvasSizeControls: View {
    let model: EditorModel
    @State private var showsPicker = false

    private var canvas: CanvasSpec { model.project.canvas }
    private var size: PixelSize? { model.session.canvasSize }

    var body: some View {
        Button {
            showsPicker.toggle()
        } label: {
            HStack(spacing: 12) {
                RatioGlyph(ratio: size?.aspectRatio ?? 1, isHighlighted: true)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(UIStrings.canvasValue(canvas))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                        .lineLimit(1)
                    if let size {
                        Text("\(UIStrings.pixelSize(width: size.width, height: size.height)) px")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(UIStrings.canvasSizeAccessibility(canvas, size: size))
        .popover(isPresented: $showsPicker, arrowEdge: .leading) {
            CanvasSizePopover(model: model)
        }
    }
}

/// A rounded rectangle with the given width / height ratio, fitted into its frame.
struct RatioGlyph: View {
    let ratio: Double
    var isHighlighted = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let safe = ratio.isFinite && ratio > 0 ? ratio : 1
            let width = safe >= 1 ? side : side * safe
            let height = safe >= 1 ? side / safe : side
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Color.accentColor : Color(nsColor: SunshotPalette.controlStroke),
                            lineWidth: 1.2)
                }
                .frame(width: max(width, 4), height: max(height, 4))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// Search, custom W × H, and the preset grid (Auto first, then General / Social / App stores).
struct CanvasSizePopover: View {
    let model: EditorModel
    @State private var query = ""
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var customError: String?
    @State private var cursor: Int?
    @FocusState private var gridFocused: Bool

    private static let columnCount = 4
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    private static let autoID = "auto"

    private var sections: [(group: CanvasPresetGroup, presets: [CanvasPreset])] {
        CanvasPresetLibrary.shared.sections(matching: query)
    }

    private var showsAuto: Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty || UIStrings.auto.lowercased().contains(needle)
    }

    /// Tile ids in visual order, for arrow-key movement.
    private var order: [String] { (showsAuto ? [Self.autoID] : []) + sections.flatMap { $0.presets.map(\.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            customSizeRow
            ScrollView {
                if order.isEmpty {
                    Text(UIStrings.noSizesMatch)
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    grid
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: 380)
        }
        .padding(14)
        .frame(width: 400)
        .onAppear(perform: syncCustomFields)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .accessibilityHidden(true)
            TextField(UIStrings.searchSizes, text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel(UIStrings.searchSizes)
                .onKeyPress(.downArrow) {
                    gridFocused = true
                    cursor = order.isEmpty ? nil : 0
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .accessibilityLabel(UIStrings.clearSearch)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var customSizeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ControlCaption(UIStrings.customSize)
            HStack(spacing: 8) {
                sideField(UIStrings.widthField, text: $widthText, accessibility: UIStrings.widthAccessibility)
                Text("×").foregroundStyle(Color(nsColor: SunshotPalette.secondaryText)).accessibilityHidden(true)
                sideField(UIStrings.heightField, text: $heightText, accessibility: UIStrings.heightAccessibility)
                Text("px").font(.callout).foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                Spacer(minLength: 0)
                Button(UIStrings.setCustomSize, action: applyCustom)
                    .buttonStyle(.glass)
            }
            if let customError {
                Label(customError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func sideField(_ title: String, text: Binding<String>, accessibility: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                .accessibilityHidden(true)
            TextField(UIStrings.auto, text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.callout.monospacedDigit())
                .frame(width: 72)
                .onSubmit(applyCustom)
                .accessibilityLabel(accessibility)
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsAuto {
                LazyVGrid(columns: columns, spacing: 8) {
                    SizeTile(
                        ratio: autoRatio, title: UIStrings.auto, subtitle: UIStrings.autoDescription,
                        isSelected: model.project.canvas == .auto, isCursor: gridFocused && current == Self.autoID,
                        accessibility: UIStrings.presetAccessibilityAuto(size: autoSize)
                    ) { select(Self.autoID) }
                }
            }
            ForEach(sections, id: \.group.id) { section in
                VStack(alignment: .leading, spacing: 6) {
                    ControlCaption(section.group.name)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(section.presets) { preset in
                            SizeTile(
                                ratio: preset.ratio, title: preset.sizeLabel, subtitle: preset.name,
                                isSelected: model.project.canvas.preset?.id == preset.id,
                                isCursor: gridFocused && current == preset.id,
                                accessibility: UIStrings.presetAccessibility(
                                    preset, size: model.canvasSize(for: preset))
                            ) { select(preset.id) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(section.group.name)
            }
        }
        .padding(2)
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.return) {
            guard let current else { return .ignored }
            select(current)
            return .handled
        }
    }

    private var current: String? { cursor.flatMap { order.indices.contains($0) ? order[$0] : nil } }

    private var autoSize: PixelSize? {
        guard let content = model.session.document.content else { return nil }
        var project = model.project
        project.canvas = .auto
        return CanvasLayout.compute(contentSize: content.pixelSize, project: project).canvasSize
    }

    private var autoRatio: Double { autoSize?.aspectRatio ?? 1 }

    private func move(_ direction: GridNavigation.Direction) -> KeyPress.Result {
        cursor = GridNavigation.move(from: cursor, direction, count: order.count, columns: Self.columnCount)
        return .handled
    }

    private func select(_ id: String) {
        customError = nil
        if id == Self.autoID {
            model.perform { $0.resetCanvas() }
        } else if let preset = CanvasPresetLibrary.shared.catalog?.preset(id: id) {
            model.perform { $0.selectCanvasPreset(preset) }
        }
        cursor = order.firstIndex(of: id)
        syncCustomFields()
    }

    private func applyCustom() {
        if model.setCustomCanvas(width: widthText, height: heightText) {
            customError = nil
        } else {
            customError = UIStrings.customSizeInvalid
            syncCustomFields()
        }
    }

    /// Shows the current custom size in the fields (empty = Auto).
    private func syncCustomFields() {
        if case .custom(let custom) = model.project.canvas {
            widthText = custom.width.map(String.init) ?? ""
            heightText = custom.height.map(String.init) ?? ""
        } else {
            widthText = ""
            heightText = ""
        }
    }
}

/// One preset in the grid: a shape in the preset's proportions, its ratio (or exact size) and its name.
struct SizeTile: View {
    let ratio: Double
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isCursor: Bool
    let accessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RatioGlyph(ratio: ratio, isHighlighted: isSelected)
                    .frame(width: 34, height: 34)
                Text(title)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(nsColor: SunshotPalette.primaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if isSelected || isCursor {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color(nsColor: SunshotPalette.selectionRing),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1.5, dash: isSelected ? [] : [4, 3]))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(accessibility)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
