import CoreGraphics
public import SunshotCore

/// S10: the non-destructive crop, applied on the single render path. The content image is cut to the crop rect
/// (sharing the original pixels) and the annotations — which live in uncropped content pixels — are shifted by
/// minus the crop origin, so they stay on the same image pixels whatever the crop. Redaction runs on the shifted
/// annotations over the cropped image, so it covers the same pixels too.
extension Renderer {
    /// The image and project to draw for `document`'s image content, or nil without image content.
    static func croppedContent(of document: EditorDocument) -> (CGImage, Project)? {
        guard let content = document.content else { return nil }
        guard let crop = document.effectiveCrop else { return (content.image, document.project) }
        let rect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        guard let cropped = content.image.cropping(to: rect) else { return (content.image, document.project) }
        var project = document.project
        project.annotations = project.annotations.shifted(by: AnnotationPoint(x: -Double(crop.x), y: -Double(crop.y)))
        return (cropped, project)
    }
}

extension EditorDocument {
    /// The crop that applies: limited to the image; nil when there is none, it crops nothing, or the content is
    /// not an image.
    public var effectiveCrop: CropRect? {
        guard let content, let crop, let clamped = crop.clamped(to: content.pixelSize),
            !clamped.isFull(of: content.pixelSize)
        else { return nil }
        return clamped
    }

    /// Size of the image content as drawn (after the crop); nil without image content.
    public var imageContentSize: PixelSize? {
        guard let content else { return nil }
        return effectiveCrop?.size ?? content.pixelSize
    }

    /// Where the drawn content starts inside the original image (the crop origin; zero without a crop). Annotation
    /// editing adds it to pointer positions, because annotations are stored in uncropped content pixels.
    public var contentOrigin: AnnotationPoint {
        guard let crop = effectiveCrop else { return AnnotationPoint(x: 0, y: 0) }
        return AnnotationPoint(x: Double(crop.x), y: Double(crop.y))
    }
}
