public import Foundation
import SunshotCore
public import SunshotRender

/// Backdrop actions that need more than a single `perform`: colour-panel streams, typed HEX, image import.
extension EditorModel {
    public static let backdropImageFailedTitle = "Can't use this image as a backdrop"
    /// A colour-panel edit closes (becomes one undo step) after the colour stays put this long.
    public static let continuousEditIdle: Duration = .milliseconds(600)

    /// For sources that stream values without an "ended" event (the system colour panel): the stream becomes a
    /// single undo step named `name`, closed after `idle` without changes or by any other edit, undo or redo.
    public func performContinuous(
        _ name: String, idle: Duration = EditorModel.continuousEditIdle, _ change: (inout EditorSession) -> Void
    ) {
        if let pending = pendingContinuousEdit, pending.name == name {
            pending.task.cancel()
        } else {
            finishContinuousEdit()
            session.beginGesture()
        }
        apply(change)
        let task = Task { [weak self] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            self?.finishContinuousEdit()
        }
        pendingContinuousEdit = (name, task)
    }

    /// Closes an open colour-panel edit (no-op when none is open).
    public func finishContinuousEdit() {
        guard let pending = pendingContinuousEdit else { return }
        pendingContinuousEdit = nil
        pending.task.cancel()
        session.endGesture(pending.name)
    }

    public var hasPendingContinuousEdit: Bool { pendingContinuousEdit != nil }

    /// Typed HEX for the solid colour. Returns false (nothing changes, no undo entry) when invalid.
    @discardableResult
    public func setBackdropColor(hex: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setBackdropColor(hex: hex) }
        return accepted
    }

    /// Typed gradient angle. Returns false (angle kept) for non-numeric text.
    @discardableResult
    public func setGradientAngle(text: String) -> Bool {
        var accepted = false
        perform { accepted = $0.setGradientAngle(text: text) }
        return accepted
    }

    /// Moves a focused stop by one keyboard step (0.01, ⇧: 0.1). Returns the stop's new index.
    @discardableResult
    public func nudgeGradientStop(_ index: Int, direction: Double, large: Bool) -> Int {
        let stops = project.backdropSettings.gradient.stops
        guard stops.indices.contains(index) else { return index }
        let step = large ? GradientSpec.largeKeyboardStep : GradientSpec.keyboardStep
        var newIndex = index
        perform { newIndex = $0.moveGradientStop(index, to: stops[index].position + direction * step) }
        return newIndex
    }

    // MARK: Backdrop image

    /// Decodes off-main; on failure shows "Can't use this image as a backdrop" and changes nothing.
    public func importBackdropData(_ data: Data, fileName: String?) async {
        finishContinuousEdit()
        do {
            let image = try await Task.detached(priority: .userInitiated) { try ImageLoader.load(data) }.value
            await apply { $0.setBackdropImage(image, data: data, fileName: fileName) }.value
        } catch {
            let reason = (error as? ImageLoadError)?.reason ?? error.localizedDescription
            alert = AlertContent(
                title: Self.backdropImageFailedTitle,
                message: [fileName, reason].compactMap(\.self).joined(separator: ": "))
        }
    }

    public func importBackdropFile(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            await importBackdropData(try Data(contentsOf: url), fileName: url.lastPathComponent)
        } catch {
            alert = AlertContent(
                title: Self.backdropImageFailedTitle, message: "\(url.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    /// Drop onto the backdrop well: uses the first supported image file. False (drop refused) when none is.
    @discardableResult
    public func importDroppedBackdrop(_ urls: [URL]) async -> Bool {
        guard let first = urls.first(where: isSupportedImageFile) else { return false }
        await importBackdropFile(at: first)
        return true
    }
}
