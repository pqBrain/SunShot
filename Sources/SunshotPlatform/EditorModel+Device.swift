public import CoreGraphics
public import SunshotCore
import SunshotRender

/// S12: device mockups in the inspector — picker tiles, finish, orientation, arrangement and the suggestion for
/// the imported media.
extension EditorModel {
    public var deviceCatalog: DeviceCatalog { .bundled }

    /// The device in use, if any.
    public var device: DeviceSelection? { project.frame.device }

    /// One model per category, in catalog order (the picker shows None plus these).
    public var deviceModels: [DeviceModel] { deviceCatalog.models }

    public var deviceFinishes: [DeviceFinish] { deviceCatalog.finishes }

    /// Arrangements offered for the current device.
    public var deviceArrangements: [DeviceArrangement] {
        guard let device else { return [] }
        return deviceCatalog.arrangements(for: device.model)
    }

    /// Whether the current device can be turned to landscape.
    public var canTurnDevice: Bool {
        device.flatMap { deviceCatalog.model($0.model) }?.rotatable ?? false
    }

    /// "Best with 1080 × 2340 px" for the current device and orientation.
    public var recommendedMediaSize: PixelSize? {
        guard let device,
            let model = deviceCatalog.model(deviceCatalog.arrangement(device.arrangement)?.primaryModel ?? device.model)
        else { return nil }
        return model.oriented(landscape: device.landscape).recommendedSize
    }

    /// The device that matches the image content, when the setting is on, there is no device yet, and the media
    /// matches one (Settings ▸ Suggest the device that matches imported media).
    public func deviceSuggestion(enabled: Bool) -> DeviceSuggestion? {
        guard enabled, device == nil, session.document.content != nil,
            let size = session.document.contentPixelSize
        else { return nil }
        return DeviceSuggestion.suggest(for: size, catalog: deviceCatalog)
    }

    @discardableResult
    public func setDevice(_ model: String?) -> Task<Void, Never> {
        perform { $0.setDevice(model, catalog: deviceCatalog) }
    }

    @discardableResult
    public func applyDeviceSuggestion(_ suggestion: DeviceSuggestion) -> Task<Void, Never> {
        perform { $0.applyDeviceSuggestion(suggestion) }
    }

    @discardableResult
    public func setDeviceFinish(_ finish: String) -> Task<Void, Never> {
        perform { $0.setDeviceFinish(finish, catalog: deviceCatalog) }
    }

    @discardableResult
    public func setDeviceLandscape(_ landscape: Bool) -> Task<Void, Never> {
        perform { $0.setDeviceLandscape(landscape, catalog: deviceCatalog) }
    }

    @discardableResult
    public func setDeviceArrangement(_ id: String) -> Task<Void, Never> {
        perform { $0.setDeviceArrangement(id, catalog: deviceCatalog) }
    }

    /// Picker tile for `model` in the current finish (sample content, cached per model / finish / orientation).
    public func deviceThumbnail(_ model: DeviceModel) -> CGImage? {
        let finish = device?.finish ?? DeviceCatalog.defaultFinishID
        let landscape = model.rotatable && (device?.landscape ?? false)
        let key = "\(model.id)/\(finish)/\(landscape)"
        if let image = templates.deviceTiles[key] { return image }
        guard let image = try? TemplateThumbnails.renderDevice(model, finish: finish, landscape: landscape) else {
            return nil
        }
        templates.deviceTiles[key] = image
        return image
    }
}
