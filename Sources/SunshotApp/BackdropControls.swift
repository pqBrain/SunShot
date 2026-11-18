import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Backdrop section: type picker, then the controls for the chosen type. Each type remembers its last settings.
struct BackdropControls: View {
    let model: EditorModel

    private var settings: BackdropSettings { model.project.backdropSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // S17: the system segmented control needs ~262 pt for four segments (even at small size) and widened the
            // whole Backdrop card past the 240 pt column; this one shares the column's width.
            CompactSegmentedPicker(
                title: UIStrings.backdropType, options: BackdropKind.allCases,
                selection: Binding(get: { settings.kind }, set: { kind in model.perform { $0.setBackdropKind(kind) } }),
                label: UIStrings.backdropKindName
            )
            .accessibilityValue(UIStrings.backdropKindName(settings.kind))

            switch settings.kind {
            case .none:
                Text(UIStrings.noneHint)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            case .solid:
                SolidBackdropControls(model: model)
            case .gradient:
                GradientControls(model: model)
            case .image:
                ImageBackdropControls(model: model)
            }
            BackdropEffectsControls(model: model)
            AutoBackgroundControls(model: model)
        }
        .animation(.smooth(duration: 0.2), value: settings.kind)
    }
}

/// Small caption above a group of controls.
struct ControlCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A `ColorPicker` (system colour panel, with opacity) whose stream of changes becomes one undo step.
struct BackdropColorWell: View {
    let model: EditorModel
    let title: String
    let color: RGBAColor
    let actionName: String
    let apply: (inout EditorSession, RGBAColor) -> Void

    var body: some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { Color(nsColor: color.nsColor) },
                set: { newValue in
                    guard let picked = RGBAColor(nsColor: NSColor(newValue)), picked != color else { return }
                    model.performContinuous(actionName) { apply(&$0, picked) }
                }),
            supportsOpacity: true
        )
        .labelsHidden()
        .accessibilityLabel(title)
        .accessibilityValue(color.hexString)
    }
}

struct SolidBackdropControls: View {
    let model: EditorModel
    @State private var hexText = ""

    private var color: RGBAColor { model.project.backdropSettings.solidColor }
    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(BackdropLibrary.shared.swatchGroups) { group in
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(group.swatches) { swatch in
                        SwatchButton(swatch: swatch, isSelected: swatch.color == color) {
                            model.perform { $0.setBackdropColor(swatch.color) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(group.name)
            }

            HStack(spacing: 10) {
                BackdropColorWell(
                    model: model, title: UIStrings.customColor, color: color,
                    actionName: EditorSession.backdropColorActionName
                ) { session, picked in session.setBackdropColor(picked) }
                Text(UIStrings.hexField)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
                TextField(UIStrings.hexField, text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .onSubmit { if !model.setBackdropColor(hex: hexText) { hexText = color.hexString } }
                    .accessibilityLabel(UIStrings.hexFieldAccessibility)
            }
        }
        .onAppear { hexText = color.hexString }
        .onChange(of: color) { _, value in hexText = value.hexString }
    }
}

struct SwatchButton: View {
    let swatch: Swatch
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: swatch.color.nsColor))
                .overlay { Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
                .padding(isSelected ? 3 : 0)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color(nsColor: SunshotPalette.selectionRing), lineWidth: 2)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("\(swatch.name) \(swatch.color.hexString)")
        .accessibilityLabel(UIStrings.swatch(name: swatch.name, hex: swatch.color.hexString, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A 16:10 tile showing a backdrop thumbnail (gradient preset or wallpaper) with a selection ring.
struct BackdropTile: View {
    let image: CGImage?
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 2).resizable()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            }
            .padding(3)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: SunshotPalette.selectionRing), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ImageBackdropControls: View {
    let model: EditorModel
    @State private var isDropTargeted = false

    private var settings: BackdropSettings { model.project.backdropSettings }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            imageWell
            Button {
                Task { await Panels.chooseBackdropImage(for: model) }
            } label: {
                Label(UIStrings.chooseBackdropImage, systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.regular)

            ControlCaption(UIStrings.wallpapers)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(BackdropLibrary.shared.wallpapers) { wallpaper in
                    let selected = settings.image == .wallpaper(wallpaper)
                    BackdropTile(
                        image: BackdropLibrary.shared.thumbnail(for: wallpaper),
                        label: UIStrings.wallpaper(wallpaper.name, selected: selected), isSelected: selected
                    ) { model.perform { $0.setWallpaper(wallpaper) } }
                }
            }
        }
    }

    private var imageWell: some View {
        ZStack {
            if let media = model.session.backdropMedia {
                Image(decorative: media.image, scale: 1).resizable().scaledToFill()
            } else if case .wallpaper(let wallpaper) = settings.image,
                let thumbnail = BackdropLibrary.shared.thumbnail(for: wallpaper)
            {
                Image(decorative: thumbnail, scale: 2).resizable().scaledToFill()
            }
            if isDropTargeted || model.session.backdropMedia == nil {
                Label(UIStrings.backdropDropHint, systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color(nsColor: SunshotPalette.dropZoneHighlight) : .black.opacity(0.12),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 0.5))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.contains(where: isSupportedImageFile) else { return false }
            Task { await model.importDroppedBackdrop(urls) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UIStrings.backdropDropHint)
        .accessibilityValue(UIStrings.backdropImageName(model.session.backdropMedia?.reference.fileName))
    }
}
