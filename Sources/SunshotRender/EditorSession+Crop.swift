public import SunshotCore

/// Crop edits (S10). One named undo step each; edits that change nothing record nothing.
extension EditorSession {
    public static let cropActionName = "Crop Image"
    public static let removeCropActionName = "Remove Crop"

    /// The current crop, limited to the image (nil = whole image).
    public var crop: CropRect? { document.effectiveCrop }

    /// Whether the content can be cropped (image content only; snippets are laid out, not cropped).
    public var canCrop: Bool { document.content != nil }

    /// Sets the crop. A crop covering the whole image is stored as no crop, so "uncropped" has one representation.
    public mutating func setCrop(_ crop: CropRect?) {
        guard let content = document.content else { return }
        let size = content.pixelSize
        let normalized = crop.flatMap { $0.clamped(to: size) }.flatMap { $0.isFull(of: size) ? nil : $0 }
        let name = normalized == nil ? Self.removeCropActionName : Self.cropActionName
        history.applyIfChanged(name) { $0.crop = normalized }
    }

    public mutating func removeCrop() { setCrop(nil) }
}
