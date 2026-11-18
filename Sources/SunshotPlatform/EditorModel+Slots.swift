public import CoreGraphics
public import Foundation
public import SunshotCore
import SunshotRender

/// One row of the Screenshots section: a slot, its title and the image it shows (nil = the main image).
public struct ScreenshotRow: Identifiable, Sendable {
    public let slot: ContentSlot
    public let name: String
    /// The slot's own image; nil for the main slot and for slots that show the main image.
    public let image: CGImage?

    public var id: Int { slot.number }
}

/// S15: several screenshots in one document — the Screenshots inspector section.
extension EditorModel {
    public var collageCatalog: CollageCatalog { .bundled }

    /// The screenshot layout in use (nil while a device is set or with one screenshot).
    public var collage: CollageArrangement? { session.collage }

    /// Rows for the active arrangement: the main screenshot, then the others by number.
    public var screenshotRows: [ScreenshotRow] {
        session.contentSlots.sorted { $0.number < $1.number }.map { slot in
            ScreenshotRow(
                slot: slot, name: UIStrings.screenshotName(number: slot.number),
                image: slot.isPrimary ? nil : session.document.slots[slot.number]?.image)
        }
    }

    /// The main image (thumbnail of the main row).
    public var mainImage: CGImage? { session.document.content?.image }

    @discardableResult
    public func setCollage(_ id: String?) -> Task<Void, Never> {
        perform { $0.setCollage(id, catalog: collageCatalog) }
    }

    /// Whether screenshot `number` can be removed: any screenshot with an image, while another image remains.
    public func canRemoveScreenshot(_ number: Int) -> Bool {
        guard session.document.canAddScreenshots, !session.document.slots.isEmpty else { return false }
        return number == 0 || session.document.slots[number] != nil
    }

    @discardableResult
    public func removeScreenshot(at number: Int) -> Task<Void, Never> {
        perform { $0.removeScreenshot(at: number) }
    }

    /// Drop of row `from` onto row `to` in the Screenshots list: the two screenshots swap places.
    @discardableResult
    public func moveScreenshot(from: Int, to: Int) -> Task<Void, Never> {
        perform { $0.moveScreenshot(from: from, to: to) }
    }

    /// Reads `url` into screenshot `number`; an unreadable file shows an alert and changes nothing.
    public func importSlotFile(at url: URL, number: Int) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            // Read and decode off the main actor: a large or network-mounted file must not freeze the studio.
            let (data, image) = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url)
                return (data, try ImageLoader.load(data))
            }.value
            finishContinuousEdit()
            session.setSlotImage(image, data: data, at: number)
        } catch {
            alert = AlertContent(
                title: UIStrings.screenshotFailedTitle,
                message: "\(url.lastPathComponent): \(error.localizedDescription)")
        }
        await refreshPreview()
    }

    /// Drop onto a slot row: uses the first supported image file. False (drop refused) when none is.
    @discardableResult
    public func importDroppedSlot(_ urls: [URL], number: Int) async -> Bool {
        guard let first = urls.first(where: isSupportedImageFile) else { return false }
        await importSlotFile(at: first, number: number)
        return true
    }

    /// Paste and capture: the first image becomes the content, every later one is added as the next screenshot
    /// (the layout grows as needed). A solid-colour border (a copied canvas backdrop, a desktop strip) is trimmed
    /// off first; the trimmed image is stored as PNG. A short notice says where it went and whether it was trimmed.
    func addScreenshot(
        _ image: CGImage, data: Data?, replacingName actionName: String, trims: Bool = true, plainFrame: Bool = false
    ) async {
        let trimmed = trims ? await Task.detached(priority: .userInitiated) { ImageTrimmer.trimmed(image) }.value : nil
        finishContinuousEdit()
        let result = session.addScreenshot(
            trimmed ?? image, data: trimmed == nil ? data : nil, replacingName: actionName, plainFrame: plainFrame)
        switch result {
        case .main: notice = trimmed == nil ? nil : UIStrings.screenshotTrimmed
        case .added(let number):
            notice = UIStrings.screenshotAdded(number: number, layout: layoutName, trimmed: trimmed != nil)
        case .full: notice = UIStrings.screenshotsFull(count: session.contentSlots.count)
        }
    }

    /// Name of the active multi-screenshot arrangement, for notices.
    private var layoutName: String? {
        if let device {
            return deviceCatalog.arrangement(device.arrangement)?.name
        }
        return collage?.name
    }
}

/// The drag payload of a Screenshots row: plain text naming the screenshot, so it needs no custom type and a file
/// dropped on a row is still told apart.
public enum ScreenshotDrag {
    static let prefix = "sunshot-screenshot:"

    public static func payload(number: Int) -> String { "\(prefix)\(number)" }

    /// The screenshot number a payload names, or nil for any other text.
    public static func number(from payload: String) -> Int? {
        guard payload.hasPrefix(prefix), let number = Int(payload.dropFirst(prefix.count)), number >= 0 else {
            return nil
        }
        return number
    }
}
