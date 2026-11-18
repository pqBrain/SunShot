public import SunshotCore

/// S12: device mockups and templates. Each edit is one named undo step; edits that change nothing record nothing.
/// A device replaces the frame chrome, so choosing a device sets the frame kind to none, and choosing a frame
/// kind (`setFrameKind`) removes the device.
extension EditorSession {
    public static let deviceActionName = "Change Device"
    public static let removeDeviceActionName = "Remove Device"
    public static let deviceFinishActionName = "Change Device Finish"
    public static let deviceOrientationActionName = "Change Device Orientation"
    public static let deviceArrangementActionName = "Change Device Layout"

    public static func applyTemplateActionName(_ name: String) -> String { "Apply Template \(name)" }

    /// The device mockup in use, if any.
    public var device: DeviceSelection? { document.project.frame.device }

    /// Shows the content on `model` (nil removes the device). The finish is kept; the orientation is kept for
    /// devices that turn; an arrangement that forces another model falls back to a single device.
    public mutating func setDevice(_ model: String?, catalog: DeviceCatalog = .bundled) {
        guard let model else {
            editProject(Self.removeDeviceActionName) { $0.frame.device = nil }
            return
        }
        guard let entry = catalog.model(model) else { return }
        let current = device
        var selection = DeviceSelection(model: model, finish: current?.finish ?? DeviceCatalog.defaultFinishID)
        selection.landscape = entry.rotatable && (current?.landscape ?? false)
        if let id = current?.arrangement, catalog.arrangements(for: model).contains(where: { $0.id == id }) {
            selection.arrangement = id
        }
        select(selection, name: Self.deviceActionName)
    }

    /// Shows the content on a suggested device (keeping a chosen finish): one "Change Device" step.
    public mutating func applyDeviceSuggestion(_ suggestion: DeviceSuggestion) {
        select(
            suggestion.selection(finish: device?.finish ?? DeviceCatalog.defaultFinishID), name: Self.deviceActionName)
    }

    public mutating func setDeviceFinish(_ finish: String, catalog: DeviceCatalog = .bundled) {
        guard var selection = device, catalog.finish(finish) != nil else { return }
        selection.finish = finish
        select(selection, name: Self.deviceFinishActionName)
    }

    /// Portrait or landscape; ignored for devices that don't turn (laptops, monitors).
    public mutating func setDeviceLandscape(_ landscape: Bool, catalog: DeviceCatalog = .bundled) {
        guard var selection = device, catalog.model(selection.model)?.rotatable == true else { return }
        selection.landscape = landscape
        select(selection, name: Self.deviceOrientationActionName)
    }

    /// Single, pair, trio or a fixed combination (which also selects its primary model).
    public mutating func setDeviceArrangement(_ id: String, catalog: DeviceCatalog = .bundled) {
        guard var selection = device, let arrangement = catalog.arrangement(id) else { return }
        selection.arrangement = id
        if let model = arrangement.primaryModel {
            selection.model = model
            if catalog.model(model)?.rotatable != true { selection.landscape = false }
        }
        select(selection, name: Self.deviceArrangementActionName)
    }

    private mutating func select(_ selection: DeviceSelection, name: String) {
        editProject(name) { project in
            project.frame.device = selection
            project.frame.kind = .none
            project.collage = nil  // S15: a device and a screenshot layout are mutually exclusive.
        }
    }

    // MARK: Templates

    /// The style a template gives this document: the template's project, keeping what belongs to the content
    /// (annotations, frame title) and the user's export choices.
    public static func project(_ template: DocumentTemplate, keeping current: Project) -> Project {
        var project = template.project
        project.annotationLayer = current.annotationLayer
        project.frame.title = current.frame.title
        project.export = current.export
        return project
    }

    /// Applies `template` to the open document as one undo step; the content is kept .
    public mutating func applyTemplate(_ template: DocumentTemplate) {
        let project = Self.project(template, keeping: document.project)
        history.applyIfChanged(Self.applyTemplateActionName(template.name)) { document in
            document.project = project
        }
    }

    /// A new, empty document in `template` (File ▸ New, Start Over and launch use the default template).
    public static func document(for template: DocumentTemplate?) -> EditorDocument {
        EditorDocument(project: template?.project ?? Project())
    }
}
