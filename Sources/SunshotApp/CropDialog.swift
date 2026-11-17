import SunshotCore
import SunshotPlatform
import SwiftUI

/// Edit ▸ Crop… (S10): the full original image with the crop rectangle on top. Ratio presets, Reset, Apply
/// (one undo step) and Cancel. Tall images fill the width and scroll. All maths is in `CropEditor` / Core.
struct CropDialog: View {
    let model: EditorModel
    private static let maxWidth: Double = 720
    private static let maxHeight: Double = 520

    private var crop: CropEditor { model.crop }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(UIStrings.cropTitle).font(.headline)
                Spacer()
                Text(crop.sizeLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            }
            Picker(UIStrings.cropRatio, selection: aspectBinding) {
                ForEach(CropAspect.allCases, id: \.self) { Text(UIStrings.cropAspectName($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(UIStrings.cropRatio)

            if let image = model.cropSourceImage {
                let display = CropDisplay(
                    imageSize: crop.imageSize, maxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
                let size = CGSize(
                    width: Double(crop.imageSize.width) * display.scale,
                    height: Double(crop.imageSize.height) * display.scale)
                Group {
                    if display.scrolls {
                        ScrollView(.vertical) { CropCanvas(image: image, size: size, display: display, crop: crop) }
                            .frame(height: Self.maxHeight)
                    } else {
                        CropCanvas(image: image, size: size, display: display, crop: crop)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text(UIStrings.cropHint)
                .font(.caption)
                .foregroundStyle(Color(nsColor: SunshotPalette.secondaryText))
            HStack {
                Button(UIStrings.cropReset) { crop.reset() }
                    .accessibilityLabel(UIStrings.cropResetAccessibility)
                Spacer()
                Button(UIStrings.cancel, role: .cancel) { model.cancelCrop() }
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.cropApply) { model.applyCrop() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: Self.maxWidth + 40)
    }

    private var aspectBinding: Binding<CropAspect> {
        Binding(get: { crop.aspect }, set: { crop.setAspect($0) })
    }
}

/// The image with the dimmed outside, the crop frame and its handles. Drags are in view points, converted to
/// content pixels by `CropDisplay`.
private struct CropCanvas: View {
    let image: CGImage
    let size: CGSize
    let display: CropDisplay
    let crop: CropEditor
    @State private var dragging = false
    private static let handleTolerance: Double = 10

    var body: some View {
        let rect = display.viewRect(crop.draft)
        let frame = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            ForEach(Self.handlePoints(frame), id: \.self) { point in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: 10, height: 10)
                    .offset(x: point.x - 5, y: point.y - 5)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        let start = display.contentPoint(x: value.startLocation.x, y: value.startLocation.y)
                        crop.pointerDown(at: start, tolerance: Self.handleTolerance / display.scale)
                    }
                    crop.pointerDragged(
                        dx: value.translation.width / display.scale, dy: value.translation.height / display.scale)
                }
                .onEnded { _ in
                    dragging = false
                    crop.pointerUp()
                }
        )
        .accessibilityElement()
        .accessibilityLabel(UIStrings.cropArea)
        .accessibilityValue(crop.sizeLabel)
    }

    private static func handlePoints(_ frame: CGRect) -> [CGPoint] {
        [
            CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.midX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY),
            CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.midX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.midY),
        ]
    }
}
