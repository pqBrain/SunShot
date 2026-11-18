/// One device of a layout, with its parts placed in layout units.
public struct PlacedDevice: Hashable, Sendable {
    public let modelID: String
    /// Back-to-front parts, including the screen, in layout units.
    public let parts: [DevicePart]
    public let screen: DevicePart
    /// Layout units per device unit (line widths of the chrome scale with it).
    public let unit: Double
    public let isPrimary: Bool

    func scaled(by factor: Double) -> PlacedDevice {
        PlacedDevice(
            modelID: modelID, parts: parts.map { $0.scaled(by: factor) }, screen: screen.scaled(by: factor),
            unit: unit * factor, isPrimary: isPrimary)
    }
}

extension DevicePart {
    func scaled(by factor: Double) -> DevicePart {
        DevicePart(
            role: role,
            rect: LayoutRect(
                x: rect.x * factor, y: rect.y * factor, width: rect.width * factor, height: rect.height * factor),
            radius: radius * factor)
    }

    func offset(x dx: Double, y dy: Double, scale: Double) -> DevicePart {
        DevicePart(
            role: role,
            rect: LayoutRect(
                x: dx + rect.x * scale, y: dy + rect.y * scale, width: rect.width * scale,
                height: rect.height * scale),
            radius: radius * scale)
    }
}

/// Where every device of a `DeviceSelection` goes (S12), in layout units with the bounding box at 0, 0.
///
/// The primary device's screen is the content rect: the canvas lays out the screen (sized from the content, see
/// `screenSize(for:)`) plus the rest of the layout as frame insets, so device chrome grows an Auto canvas like
/// S5 frames do. Content is aspect-filled (centre-cropped) into every screen.
public struct DeviceLayout: Hashable, Sendable {
    public let width: Double
    public let height: Double
    /// Back to front.
    public let devices: [PlacedDevice]
    public let finish: DeviceFinish

    /// nil when the selection names a model, finish or arrangement the catalog doesn't have.
    public init?(selection: DeviceSelection, catalog: DeviceCatalog = .bundled) {
        guard let arrangement = catalog.arrangement(selection.arrangement),
            let finish = catalog.finish(selection.finish),
            let selected = catalog.model(arrangement.primaryModel ?? selection.model)
        else { return nil }
        let primary = selected.oriented(landscape: selection.landscape)
        var devices: [PlacedDevice] = []
        for slot in arrangement.slots {
            // Slots without a model show the selection (turned with it); fixed companions stay upright.
            let model: DeviceModel
            if slot.isPrimary {
                model = primary
            } else if let id = slot.model {
                guard let fixed = catalog.model(id) else { return nil }
                model = fixed
            } else {
                model = primary
            }
            let scale = slot.height * primary.height / model.height
            let centerX = slot.centerX * primary.width
            let centerY = slot.centerY * primary.height
            let originX = centerX - model.width * scale / 2
            let originY = centerY - model.height * scale / 2
            let parts = model.parts.map { $0.offset(x: originX, y: originY, scale: scale) }
            guard let screen = parts.first(where: { $0.role == .screen }) else { return nil }
            devices.append(
                PlacedDevice(modelID: model.id, parts: parts, screen: screen, unit: scale, isPrimary: slot.isPrimary))
        }
        let all = devices.flatMap(\.parts).map(\.rect)
        let minX = all.map(\.x).min() ?? 0
        let minY = all.map(\.y).min() ?? 0
        width = (all.map { $0.x + $0.width }.max() ?? 0) - minX
        height = (all.map { $0.y + $0.height }.max() ?? 0) - minY
        self.devices = devices.map { device in
            PlacedDevice(
                modelID: device.modelID, parts: device.parts.map { $0.offset(x: -minX, y: -minY, scale: 1) },
                screen: device.screen.offset(x: -minX, y: -minY, scale: 1), unit: device.unit,
                isPrimary: device.isPrimary)
        }
        self.finish = finish
    }

    private init(width: Double, height: Double, devices: [PlacedDevice], finish: DeviceFinish) {
        self.width = width
        self.height = height
        self.devices = devices
        self.finish = finish
    }

    /// The device mockup of `frame`, or nil when it has none (or names something unknown).
    public init?(frame: Frame, catalog: DeviceCatalog = .bundled) {
        guard let selection = frame.device else { return nil }
        self.init(selection: selection, catalog: catalog)
    }

    /// The device whose screen holds the content as laid out (validated to exist).
    public var primary: PlacedDevice? { devices.first(where: \.isPrimary) }

    /// Width ÷ height of the primary screen.
    public var screenAspect: Double {
        guard let screen = primary?.screen.rect, screen.height > 0 else { return 1 }
        return screen.width / screen.height
    }

    /// The same layout scaled uniformly by `factor`.
    public func scaled(by factor: Double) -> DeviceLayout {
        DeviceLayout(
            width: width * factor, height: height * factor, devices: devices.map { $0.scaled(by: factor) },
            finish: finish)
    }

    /// The layout scaled to fill a frame box `boxWidth` wide (the box has the layout's aspect).
    public func fitted(toWidth boxWidth: Double) -> DeviceLayout {
        scaled(by: width > 0 ? boxWidth / width : 1)
    }

    /// The primary screen size for content of `contentSize`: the largest rect of the screen's aspect inside the
    /// content (content pixels stay 1:1; the rest is cropped evenly from both sides).
    public func screenSize(for contentSize: PixelSize) -> (width: Double, height: Double) {
        let contentWidth = Double(contentSize.width)
        let contentHeight = Double(contentSize.height)
        let aspect = screenAspect
        if contentWidth / contentHeight > aspect { return (contentHeight * aspect, contentHeight) }
        return (contentWidth, contentWidth / aspect)
    }

    /// The chrome around a primary screen `screenWidth` wide, as frame insets.
    public func insets(screenWidth: Double) -> FrameInsets {
        guard let screen = primary?.screen.rect, screen.width > 0 else { return .zero }
        let factor = screenWidth / screen.width
        return FrameInsets(
            top: screen.y * factor, left: screen.x * factor,
            bottom: (height - screen.y - screen.height) * factor, right: (width - screen.x - screen.width) * factor)
    }
}

extension FrameGeometry {
    /// What the canvas lays out for content of `contentSize` under `frame`: the content (or, for a device
    /// mockup, the primary screen cut from it) and the chrome insets around it.
    public static func layoutBox(
        for frame: Frame, contentSize: PixelSize, catalog: DeviceCatalog = .bundled
    ) -> (width: Double, height: Double, insets: FrameInsets) {
        if let device = DeviceLayout(frame: frame, catalog: catalog) {
            let screen = device.screenSize(for: contentSize)
            return (screen.width, screen.height, device.insets(screenWidth: screen.width))
        }
        let width = Double(contentSize.width)
        return (width, Double(contentSize.height), insets(for: frame, contentWidth: width))
    }

    /// Like `layoutBox(for:contentSize:)`, plus the S15 screenshot layout of `project` around the frame box: the
    /// other screenshots are extra insets, so the primary content keeps its 1:1 pixels.
    public static func layoutBox(
        for project: Project, contentSize: PixelSize, catalog: DeviceCatalog = .bundled,
        collages: CollageCatalog = .bundled
    ) -> (width: Double, height: Double, insets: FrameInsets) {
        let box = layoutBox(for: project.frame, contentSize: contentSize, catalog: catalog)
        let frameWidth = box.width + box.insets.horizontal
        let frameHeight = box.height + box.insets.vertical
        guard
            let collage = CollageLayout(
                project: project, boxWidth: frameWidth, boxHeight: frameHeight, catalog: collages)
        else { return box }
        let around = collage.insets
        let insets = FrameInsets(
            top: box.insets.top + around.top, left: box.insets.left + around.left,
            bottom: box.insets.bottom + around.bottom, right: box.insets.right + around.right)
        return (box.width, box.height, insets)
    }
}
