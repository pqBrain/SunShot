public import CoreGraphics
public import Foundation
import SunshotCore

/// Captured content (S10): a screen or website capture replaces the content like an import, as one named undo
/// step, keeping the style. The PNG bytes are kept as the original media so documents save them unchanged.
extension EditorSession {
    public static let captureScreenActionName = "Capture Screenshot"
    public static let captureWebsiteActionName = "Capture Website"

    public mutating func setCapturedContent(_ image: CGImage, data: Data?, actionName: String) {
        history.apply(actionName) {
            $0.content = ContentImage(image, data: data)
            $0.snippet = nil
            $0.crop = nil
        }
    }
}
