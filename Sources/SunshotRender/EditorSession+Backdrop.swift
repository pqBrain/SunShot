public import CoreGraphics
public import Foundation
public import SunshotCore

/// Backdrop edits. Each is one named undo step; edits that change nothing record nothing. Continuous edits
/// (angle slider, stop drag) use `beginGesture` / `endGesture` like the border and shadow controls.
extension EditorSession {
    public static let backdropKindActionName = "Change Backdrop Type"
    public static let backdropColorActionName = "Change Backdrop Colour"
    public static let gradientPresetActionName = "Apply Gradient Preset"
    public static let gradientKindActionName = "Change Gradient Type"
    public static let gradientAngleActionName = "Change Gradient Angle"
    public static let addStopActionName = "Add Gradient Stop"
    public static let moveStopActionName = "Move Gradient Stop"
    public static let stopColorActionName = "Change Stop Colour"
    public static let deleteStopActionName = "Delete Gradient Stop"
    public static let backdropImageActionName = "Choose Backdrop Image"
    public static let wallpaperActionName = "Choose Wallpaper"
    public static let resetBackdropActionName = "Reset Backdrop"

    public var backdropSettings: BackdropSettings { project.backdropSettings }

    /// Switches type, restoring that type's last-used settings.
    public mutating func setBackdropKind(_ kind: BackdropKind) {
        editProject(Self.backdropKindActionName) { $0.backdropSettings.kind = kind }
    }

    /// Sets a solid colour (swatch, colour panel or typed HEX) and selects the Solid type.
    public mutating func setBackdropColor(_ color: RGBAColor) {
        editProject(Self.backdropColorActionName) { $0.backdrop = .solid(color) }
    }

    /// Typed HEX (`#1A2B3C`, `1A2B3C`, `#1a2b3c80`). Invalid text is rejected (false) without an undo entry.
    @discardableResult
    public mutating func setBackdropColor(hex: String) -> Bool {
        guard let color = RGBAColor(hex: hex) else { return false }
        setBackdropColor(color)
        return true
    }

    /// Replaces the whole gradient (kind, angle and stops) and selects the Gradient type.
    public mutating func applyGradientPreset(_ spec: GradientSpec) {
        editProject(Self.gradientPresetActionName) { $0.backdrop = .gradient(spec) }
    }

    public mutating func setGradientKind(_ kind: GradientKind) {
        editGradient(Self.gradientKindActionName) { $0.kind = kind }
    }

    public mutating func setGradientAngle(_ degrees: Double) {
        editGradient(Self.gradientAngleActionName) { $0.angle = degrees }
    }

    /// Typed angle ("140", "140°"). Non-numeric text is rejected (false) and the angle is kept.
    @discardableResult
    public mutating func setGradientAngle(text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("°") { trimmed.removeLast() }
        guard let value = Double(trimmed.trimmingCharacters(in: .whitespaces)), value.isFinite else { return false }
        setGradientAngle(value)
        return true
    }

    /// Adds a stop coloured as the gradient is at `position`. Returns its index (nil at 12 stops).
    @discardableResult
    public mutating func addGradientStop(at position: Double) -> Int? {
        var index: Int?
        editGradient(Self.addStopActionName) { index = $0.addStop(at: position) }
        return index
    }

    /// Moves a stop (positions clamp to 0…1, stops stay sorted). Returns the stop's new index.
    @discardableResult
    public mutating func moveGradientStop(_ index: Int, to position: Double) -> Int {
        var newIndex = index
        editGradient(Self.moveStopActionName) { newIndex = $0.moveStop(index, to: position) }
        return newIndex
    }

    public mutating func setGradientStopColor(_ index: Int, _ color: RGBAColor) {
        editGradient(Self.stopColorActionName) { $0.setStopColor(index, color) }
    }

    /// Deletes a stop; refused (false) when only 2 remain.
    @discardableResult
    public mutating func deleteGradientStop(_ index: Int) -> Bool {
        var deleted = false
        editGradient(Self.deleteStopActionName) { deleted = $0.deleteStop(index) }
        return deleted
    }

    /// Uses one of Sunshot's generated wallpapers and selects the Image type.
    public mutating func setWallpaper(_ wallpaper: Wallpaper) {
        editDocument(Self.wallpaperActionName) { $0.project.backdrop = .image(.wallpaper(wallpaper)) }
    }

    /// Uses a decoded user image as the backdrop; `data` (the original file bytes) is kept in the document.
    public mutating func setBackdropImage(_ image: CGImage, data: Data, fileName: String?) {
        let reference = MediaReference(
            id: UUID().uuidString, fileName: fileName, pixelSize: PixelSize(width: image.width, height: image.height))
        editDocument(Self.backdropImageActionName) { document in
            document.media[reference.id] = MediaAsset(reference: reference, data: data, image: image)
            document.project.backdrop = .image(.file(reference))
        }
    }

    /// Decodes `data` and uses it as the backdrop. Throws (state untouched) when it isn't a usable image.
    public mutating func importBackdropImage(data: Data, fileName: String?) throws {
        setBackdropImage(try ImageLoader.load(data), data: data, fileName: fileName)
    }

    /// Back to the default (solid #EDEDF2). Other types keep their last-used values. No-op when already default.
    public mutating func resetBackdrop() {
        editProject(Self.resetBackdropActionName) { $0.backdrop = .solid(SunshotDefaults.backdropColor) }
    }

    /// The user image currently referenced by the backdrop settings, if any.
    public var backdropMedia: MediaAsset? {
        backdropSettings.mediaReference.flatMap { document.media[$0.id] }
    }

    // MARK: Helpers

    /// Gradient edits also select the Gradient type.
    private mutating func editGradient(_ name: String, _ change: (inout GradientSpec) -> Void) {
        editProject(name) { project in
            var spec = project.backdropSettings.gradient
            change(&spec)
            project.backdrop = .gradient(spec)
        }
    }

    /// Edits that touch media too. Media no longer referenced by the settings is dropped (undo keeps old states).
    private mutating func editDocument(_ name: String, _ change: (inout EditorDocument) -> Void) {
        history.applyIfChanged(name) { document in
            change(&document)
            let keep = document.project.backdropSettings.mediaReference?.id
            document.media = document.media.filter { $0.key == keep }
        }
    }
}
