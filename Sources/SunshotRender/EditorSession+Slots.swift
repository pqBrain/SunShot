public import CoreGraphics
public import Foundation
public import SunshotCore

extension EditorDocument {
    /// The slot images the active arrangement draws (S15), keyed by arrangement slot index. `slots` is keyed by
    /// screenshot number (1, 2…), so images keep their order when a layout grows or changes.
    public var slotImages: [Int: CGImage] {
        guard !slots.isEmpty else { return [:] }
        var images: [Int: CGImage] = [:]
        for slot in project.contentSlots() where !slot.isPrimary {
            if let image = slots[slot.number]?.image { images[slot.index] = image }
        }
        return images
    }

    /// True when the content is a still image (not a code snippet or a video), so screenshots can be added.
    public var canAddScreenshots: Bool { content != nil && snippet == nil && activeVideo == nil }
}

/// What `addScreenshot` did.
public enum AddScreenshotResult: Equatable, Sendable {
    /// The document had no image content: the image became the main content.
    case main
    /// The image went into screenshot `number` (the layout grew if it had to).
    case added(number: Int)
    /// Every arrangement is full; nothing changed.
    case full
}

/// S15: several screenshots in one document. Each edit is one named undo step; edits that change nothing record
/// nothing. A screenshot layout and a device mockup are mutually exclusive (see `setDevice`).
extension EditorSession {
    public static let setSlotActionName = "Set Screenshot"
    public static let removeSlotActionName = "Remove Screenshot"
    public static let moveSlotActionName = "Move Screenshot"
    public static let collageActionName = "Change Screenshot Layout"
    public static let addScreenshotActionName = "Add Screenshot"

    /// The slots of the active arrangement (one primary slot when there is no multi-slot arrangement).
    public var contentSlots: [ContentSlot] { document.project.contentSlots() }

    /// The screenshot layout in use, if any (nil while a device is set).
    public var collage: CollageArrangement? {
        guard document.project.frame.device == nil else { return nil }
        return CollageCatalog.bundled.arrangement(document.project.collage)
    }

    /// Shows `image` as screenshot `number`. Ignored for the main screenshot (0) and numbers the active
    /// arrangement doesn't have.
    public mutating func setSlotImage(_ image: CGImage, data: Data? = nil, at number: Int) {
        guard number > 0, contentSlots.contains(where: { $0.number == number }) else { return }
        history.apply(Self.setSlotActionName) { $0.slots[number] = ContentImage(image, data: data) }
    }

    /// Decodes `data` and shows it as screenshot `number`. Throws without touching state if it isn't an image.
    public mutating func importSlotImage(data: Data, at number: Int) throws {
        setSlotImage(try ImageLoader.load(data), data: data, at: number)
    }

    /// Removes screenshot `number` (0 = the main one) as one undo step: the later screenshots move up one place
    /// (the next becomes the main image), and the layout shrinks to fit (one screenshot = no layout). The last
    /// remaining image can't be removed here (that is Clear Content); an empty slot changes nothing.
    public mutating func removeScreenshot(at number: Int) {
        guard document.canAddScreenshots, let main = document.content else { return }
        var sequence: [ContentImage] = [main] + document.slots.sorted { $0.key < $1.key }.map(\.value)
        let position: Int
        if number == 0 {
            position = 0
        } else {
            guard let image = document.slots[number], let index = sequence.firstIndex(of: image) else { return }
            position = index
        }
        guard sequence.count > 1 else { return }
        sequence.remove(at: position)
        let project = document.project.shrinking(toFit: sequence.count)
        history.apply(Self.removeSlotActionName) { document in
            if position == 0 { document.crop = nil }  // the crop belonged to the removed main image
            document.content = sequence[0]
            document.slots = Self.numbered(sequence.dropFirst())
            document.project = project
        }
    }

    /// Swaps screenshots `from` and `to` (0 = the main one) as one undo step "Move Screenshot" — drag and drop in
    /// the Screenshots list. Both must be slots of the active arrangement; the main slot can't be left empty.
    public mutating func moveScreenshot(from: Int, to: Int) {
        guard document.canAddScreenshots, from != to, let main = document.content else { return }
        let count = contentSlots.count
        guard (0..<count).contains(from), (0..<count).contains(to) else { return }
        var items: [ContentImage?] = (0..<count).map { $0 == 0 ? main : document.slots[$0] }
        items.swapAt(from, to)
        guard let newMain = items[0] else { return }
        history.apply(Self.moveSlotActionName) { document in
            if newMain != main { document.crop = nil }
            document.content = newMain
            for number in 1..<count { document.slots[number] = items[number] }
        }
    }

    private static func numbered<C: Collection>(_ images: C) -> [Int: ContentImage] where C.Element == ContentImage {
        var slots: [Int: ContentImage] = [:]
        for (offset, image) in images.enumerated() { slots[offset + 1] = image }
        return slots
    }

    /// Chooses a screenshot layout (nil = one screenshot). Choosing one removes the device mockup.
    public mutating func setCollage(_ id: String?, catalog: CollageCatalog = .bundled) {
        if let id, catalog.arrangement(id) == nil { return }
        editProject(Self.collageActionName) { project in
            project.collage = id
            if id != nil { project.frame.device = nil }
        }
    }

    /// Paste and capture (S15): with no image content the image becomes the main content (`actionName` names
    /// that step); otherwise it fills the first empty screenshot, growing the layout (one screenshot → side by
    /// side → row of three → grid; a device gains devices) when every slot is filled, and resets a layout preset
    /// that runs off the canvas (`ContentTransform.bleedsOffCanvas`). One undo step either way.
    @discardableResult
    public mutating func addScreenshot(
        _ image: CGImage, data: Data? = nil, replacingName actionName: String = EditorSession.importActionName,
        plainFrame: Bool = false
    ) -> AddScreenshotResult {
        guard document.canAddScreenshots else {
            let replacing = hasContent && actionName == Self.importActionName
            history.apply(replacing ? Self.replaceActionName : actionName) {
                $0.content = ContentImage(image, data: data)
                $0.snippet = nil
                $0.crop = nil
                $0.video = nil
                if plainFrame { $0.project.frame.kind = .none }
            }
            return .main
        }
        var project = document.project
        var number = Self.firstEmpty(in: project, slots: document.slots)
        if number == nil {
            guard let grown = project.growing(toFit: project.contentSlots().count + 1) else { return .full }
            project = grown
            number = Self.firstEmpty(in: project, slots: document.slots)
        }
        guard let number else { return .full }
        // A layout preset that runs off the canvas would cut the other screenshots off: start centred instead.
        if project.placement.transform.bleedsOffCanvas { project.placement = ContentPlacement() }
        history.apply(Self.addScreenshotActionName) {
            $0.project = project
            $0.slots[number] = ContentImage(image, data: data)
        }
        return .added(number: number)
    }

    private static func firstEmpty(in project: Project, slots: [Int: ContentImage]) -> Int? {
        project.contentSlots().map(\.number).filter { $0 > 0 && slots[$0] == nil }.min()
    }
}
