public import CoreGraphics
public import Observation
public import SunshotCore
import SunshotRender

/// The crop dialog's draft (S10). Handle drags change only the draft; Apply records the crop as one undo step,
/// Cancel discards it. All maths is `CropGeometry` (Core); this holds state between pointer events.
@MainActor
@Observable
public final class CropEditor {
    /// The dialog is up.
    public var isPresented = false
    /// The crop being edited, in content pixels of the original (uncropped) image.
    public internal(set) var draft = LayoutRect(x: 0, y: 0, width: 1, height: 1)
    public internal(set) var aspect = CropAspect.free
    public internal(set) var imageSize = PixelSize(width: 1, height: 1)
    private var drag: (handle: CropHandle, start: LayoutRect)?

    public init() {}

    /// Opens the draft on the whole image, or on `crop` when the content is already cropped (re-opening shows the
    /// full image with the current crop).
    public func begin(imageSize: PixelSize, crop: CropRect?) {
        self.imageSize = imageSize
        draft = (crop?.clamped(to: imageSize) ?? CropRect(full: imageSize)).layoutRect
        aspect = .free
        drag = nil
        isPresented = true
    }

    /// Picks a ratio preset: the draft becomes the largest rect of that ratio inside it, centred.
    public func setAspect(_ aspect: CropAspect) {
        self.aspect = aspect
        draft = CropGeometry.fit(ratio: aspect.ratio(for: imageSize), inside: draft)
    }

    /// Back to the whole image, free ratio.
    public func reset() {
        aspect = .free
        draft = CropRect(full: imageSize).layoutRect
        drag = nil
    }

    /// Pointer down at `point` (content pixels). Returns the handle grabbed, nil outside the crop.
    @discardableResult
    public func pointerDown(at point: AnnotationPoint, tolerance: Double) -> CropHandle? {
        let handle = CropGeometry.handle(at: point, in: draft, tolerance: tolerance)
        drag = handle.map { ($0, draft) }
        return handle
    }

    /// Pointer moved by (`dx`, `dy`) content pixels since pointer down.
    public func pointerDragged(dx: Double, dy: Double) {
        guard let drag else { return }
        draft = CropGeometry.drag(
            drag.handle, from: drag.start, dx: dx, dy: dy, ratio: aspect.ratio(for: imageSize), imageSize: imageSize)
    }

    public func pointerUp() { drag = nil }

    /// The draft in whole pixels.
    public var result: CropRect { CropRect.rounded(draft, in: imageSize) }

    /// "1200 × 800 px".
    public var sizeLabel: String { UIStrings.pixelSize(width: result.width, height: result.height) + " px" }

    /// Whether the draft crops anything.
    public var isCropping: Bool { !result.isFull(of: imageSize) }
}

/// The crop dialog's flow on the editor (S10).
extension EditorModel {
    public var canCrop: Bool { session.canCrop && !annotate.isActive }

    /// Opens the crop dialog on the full image with the current crop.
    public func openCrop() {
        guard canCrop, let content = session.document.content else { return }
        crop.begin(imageSize: content.pixelSize, crop: session.crop)
    }

    /// Records the draft as the crop (one "Crop Image" step; a full-image draft removes the crop).
    @discardableResult
    public func applyCrop() -> Task<Void, Never> {
        let result = crop.result
        crop.isPresented = false
        return perform { $0.setCrop(result) }
    }

    public func cancelCrop() { crop.isPresented = false }

    @discardableResult
    public func removeCrop() -> Task<Void, Never> { perform { $0.removeCrop() } }

    public var isCropped: Bool { session.crop != nil }

    /// The full, uncropped content image the crop dialog shows (nil without image content).
    public var cropSourceImage: CGImage? { session.document.content?.image }
}
