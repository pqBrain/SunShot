public import Foundation

/// A Sunshot document preset (S12): a whole style — canvas, backdrop, corners, shadow, frame or device and
/// placement — with no content. Applying one keeps the user's content.
public struct DocumentTemplate: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let project: Project

    public init(id: String, name: String, summary: String, project: Project) {
        self.id = id
        self.name = name
        self.summary = summary
        self.project = project
    }

    /// Whether the template shows a device mockup (the gallery groups these).
    public var usesDevice: Bool { project.frame.device != nil }

    /// Size of the sample content used for previews when the document is empty: the recommended media of the
    /// template's device (turned with it), else a desktop window shape.
    public func sampleSize(catalog: DeviceCatalog = .bundled) -> PixelSize {
        guard let selection = project.frame.device,
            let model = catalog.model(catalog.arrangement(selection.arrangement)?.primaryModel ?? selection.model)
        else { return PixelSize(width: 1280, height: 800) }
        return model.oriented(landscape: selection.landscape).recommendedSize
    }
}

public enum TemplateCatalogError: Error, Equatable {
    case missingResource
    case invalid(String)
}

/// Sunshot's templates, shipped as bundled JSON (`templates.json`) and validated against the other catalogs
/// (gradients, wallpapers, layout presets, devices) when they load. The first template is the plain new document.
public struct TemplateCatalog: Hashable, Sendable {
    public static let resourceName = "templates"
    public static let defaultID = "screenshot"

    public let templates: [DocumentTemplate]

    public init(templates: [DocumentTemplate]) {
        self.templates = templates
    }

    /// The template for a stored setting: matched by id, or by name ignoring case (Settings saved before S12
    /// stored the name "Screenshot"). Anything unknown is the default template.
    public func template(matching key: String) -> DocumentTemplate? {
        let lowered = key.lowercased()
        return templates.first { $0.id == key } ?? templates.first { $0.name.lowercased() == lowered }
            ?? templates.first
    }

    public static func load(devices: DeviceCatalog = .bundled) throws -> TemplateCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw TemplateCatalogError.missingResource
        }
        return try decode(
            Data(contentsOf: url), gradients: try BackdropCatalog.gradientPresets(),
            wallpapers: try BackdropCatalog.wallpapers(), layouts: try LayoutPresetCatalog.load(), devices: devices)
    }

    public static func decode(
        _ data: Data, gradients: [GradientPreset], wallpapers: [Wallpaper], layouts: LayoutPresetCatalog,
        devices: DeviceCatalog
    ) throws -> TemplateCatalog {
        let file: RawFile
        do {
            file = try JSONDecoder().decode(RawFile.self, from: data)
        } catch {
            throw TemplateCatalogError.invalid("malformed JSON: \(error)")
        }
        let context = Context(gradients: gradients, wallpapers: wallpapers, layouts: layouts, devices: devices)
        let templates = try file.templates.map { try $0.template(context) }
        var ids = Set<String>()
        var names = Set<String>()
        for template in templates {
            guard !template.id.isEmpty, ids.insert(template.id).inserted else {
                throw invalid("duplicate or empty id \(template.id)")
            }
            guard !template.name.isEmpty, names.insert(template.name.lowercased()).inserted else {
                throw invalid("duplicate or empty name \(template.id)")
            }
        }
        guard let first = templates.first, first.id == defaultID, first.project == Project() else {
            throw invalid("the first template must be the plain new document")
        }
        return TemplateCatalog(templates: templates)
    }

    static func invalid(_ reason: String) -> TemplateCatalogError { .invalid(reason) }

    struct Context {
        let gradients: [GradientPreset]
        let wallpapers: [Wallpaper]
        let layouts: LayoutPresetCatalog
        let devices: DeviceCatalog
    }

    private struct RawFile: Decodable {
        let templates: [RawTemplate]
    }
}

// MARK: Template file entries

extension TemplateCatalog {
    struct RawCanvas: Decodable {
        let ratio: Double?
        let width: Int?
        let height: Int?

        func spec(_ id: String) throws -> CanvasSpec {
            switch (ratio, width, height) {
            case (let ratio?, nil, nil) where ratio.isFinite && ratio > 0:
                return .ratio(ratio)
            case (nil, let width?, let height?)
            where (1...SunshotDefaults.maxCanvasSide).contains(width)
                && (1...SunshotDefaults.maxCanvasSide).contains(height):
                return .exact(PixelSize(width: width, height: height))
            default:
                throw TemplateCatalog.invalid("bad canvas in \(id)")
            }
        }
    }

    struct RawBackdrop: Decodable {
        let solid: String?
        let gradient: String?
        let wallpaper: String?
        let none: Bool?

        func backdrop(_ id: String, _ context: Context) throws -> Backdrop {
            switch (solid, gradient, wallpaper, none) {
            case (let hex?, nil, nil, nil):
                guard let color = RGBAColor(hex: hex) else { throw TemplateCatalog.invalid("bad colour in \(id)") }
                return .solid(color)
            case (nil, let name?, nil, nil):
                guard let preset = context.gradients.first(where: { $0.id == name }) else {
                    throw TemplateCatalog.invalid("unknown gradient \(name) in \(id)")
                }
                return .gradient(preset.spec)
            case (nil, nil, let name?, nil):
                guard let wallpaper = context.wallpapers.first(where: { $0.id == name }) else {
                    throw TemplateCatalog.invalid("unknown wallpaper \(name) in \(id)")
                }
                return .image(.wallpaper(wallpaper))
            case (nil, nil, nil, true):
                return .none
            default:
                throw TemplateCatalog.invalid("a backdrop needs exactly one of solid, gradient, wallpaper, none")
            }
        }
    }

    struct RawCorners: Decodable {
        let style: CornerStyle?
        let radius: Double?
    }

    struct RawShadow: Decodable {
        let style: ShadowStyle?
        let intensity: ShadowIntensity?
    }

    struct RawTemplate: Decodable {
        let id: String
        let name: String
        let summary: String?
        let canvas: RawCanvas?
        let padding: Double?
        let backdrop: RawBackdrop?
        let corners: RawCorners?
        let shadow: RawShadow?
        let frame: String?
        let device: DeviceSelection?
        let layout: String?

        func template(_ context: Context) throws -> DocumentTemplate {
            var project = Project()
            if let canvas { project.canvas = try canvas.spec(id) }
            if let padding {
                guard padding.isFinite, (0...SunshotDefaults.maxPadding).contains(padding) else {
                    throw TemplateCatalog.invalid("bad padding in \(id)")
                }
                project.padding = padding
            }
            if let backdrop { project.backdrop = try backdrop.backdrop(id, context) }
            if let corners {
                if let radius = corners.radius, !(radius.isFinite && Border.radiusRange.contains(radius)) {
                    throw TemplateCatalog.invalid("bad corner radius in \(id)")
                }
                project.border = Border(
                    style: corners.style ?? SunshotDefaults.cornerStyle,
                    radius: corners.radius ?? SunshotDefaults.cornerRadius)
            }
            if let shadow {
                project.shadow.style = shadow.style ?? SunshotDefaults.shadowStyle
                project.shadow.intensity = shadow.intensity ?? SunshotDefaults.shadowIntensity
            }
            if let frame {
                guard let kind = FrameKind(rawValue: frame) else { throw TemplateCatalog.invalid("bad frame in \(id)") }
                project.frame.kind = kind
            }
            if let device {
                guard project.frame.kind == .none else { throw TemplateCatalog.invalid("\(id): frame and device") }
                guard DeviceLayout(selection: device, catalog: context.devices) != nil,
                    let arrangement = context.devices.arrangement(device.arrangement),
                    arrangement.primaryModel == nil || arrangement.primaryModel == device.model
                else { throw TemplateCatalog.invalid("bad device in \(id)") }
                project.frame.device = device
            }
            if let layout {
                guard let preset = context.layouts.preset(id: layout) else {
                    throw TemplateCatalog.invalid("unknown layout \(layout) in \(id)")
                }
                project.placement = ContentPlacement(transform: preset.transform, layoutPresetID: preset.id)
            }
            return DocumentTemplate(
                id: id, name: name.trimmingCharacters(in: .whitespaces), summary: summary ?? "", project: project)
        }
    }
}
