public import Foundation
import Observation
public import SunshotCore
import SunshotRender
import os

// MARK: Autosave

extension DocumentController {
    /// Re-arms on every change of the document store; each change restarts the idle timer.
    func observeDocument() {
        withObservationTracking {
            _ = model.session
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.documentDidChange()
                self?.observeDocument()
            }
        }
    }

    func documentDidChange() {
        autosaveTask?.cancel()
        guard isDirty, !isReadOnly else { return }
        let delay = autosaveDelay
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.autosave()
        }
    }

    /// Writes unsaved changes now (idle timer, app resigning active, quit): saved documents in place, untitled
    /// ones to their draft. An untitled document without content keeps no draft.
    public func autosave() async {
        guard !isReadOnly else { return }
        let document = model.session.document
        guard document != savedDocument || (fileURL == nil && document.content != nil && !draftExists) else { return }
        if fileURL == nil && document.content == nil {
            removeDraft()
            return
        }
        _ = await write(to: fileURL ?? draftURL)
    }

    var draftExists: Bool { FileManager.default.fileExists(atPath: draftURL.path) }

    /// Test hook: observe each write (argument: whether it ran on the main thread).
    func setWriteObserver(_ hook: (@Sendable (Bool) -> Void)?) async {
        await writer.setOnWrite(hook)
    }
}

// MARK: Start Over

extension DocumentController {
    /// Whether File ▸ Start Over should ask first ("Confirm before resetting" on and something to reset).
    public var startOverNeedsConfirmation: Bool {
        settings.confirmReset && model.session.canStartOver(to: defaultTemplateDocument)
    }

    /// Resets content and style to the default template (one undo step "Start Over"). Settings are untouched.
    public func startOver() {
        let start = defaultTemplateDocument
        model.perform { $0.startOver(to: start) }
    }
}

// MARK: Themes

extension DocumentController {
    public var appliedTheme: Theme? { model.session.document.theme }

    public var themeHeaderTitle: String {
        Theme.headerTitle(applied: appliedTheme, project: model.project, library: themes)
    }

    public func reloadThemes() { themes = themeStore.load() }

    public func validateThemeName(_ name: String, excluding: String? = nil) -> Result<String, ThemeName.Problem> {
        ThemeName.validate(name, existing: themes, excluding: excluding)
    }

    /// Saves the current style as `name`. With `replacing`, a theme of the same name is overwritten.
    @discardableResult
    public func saveTheme(named name: String, replacing: Bool = false) throws -> Theme {
        var id = UUID().uuidString
        switch validateThemeName(name) {
        case .success: break
        case .failure(.duplicate(let existing)) where replacing: id = existing
        case .failure(let problem): throw problem
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let theme = try Theme.extract(from: model.project, name: trimmed, id: id)
        try themeStore.save(theme)
        reloadThemes()
        model.perform { $0.markThemeSaved(theme) }
        return theme
    }

    /// Applies a saved theme's style (one undo step "Apply Theme <name>").
    public func applyTheme(_ theme: Theme) {
        model.perform { session in
            do {
                try session.applyTheme(theme)
            } catch {
                DocumentController.log.error("Theme \(theme.name, privacy: .public) can't be applied")
            }
        }
    }

    public func renameTheme(id: String, to name: String) throws {
        guard var theme = themes.first(where: { $0.id == id }) else { return }
        theme.name = try validateThemeName(name, excluding: id).get()
        try themeStore.save(theme)
        reloadThemes()
    }

    @discardableResult
    public func duplicateTheme(id: String) throws -> Theme? {
        guard let source = themes.first(where: { $0.id == id }) else { return nil }
        let copy = Theme(name: ThemeName.copyName(of: source.name, existing: themes), style: source.style)
        try themeStore.save(copy)
        reloadThemes()
        return copy
    }

    /// Deletes the theme file. A document using it keeps its style; its header becomes "No Theme".
    public func deleteTheme(id: String) throws {
        try themeStore.delete(id: id)
        reloadThemes()
    }
}

// MARK: Export destination

/// Where ⇧⌘E writes: straight into the default folder, or a save panel.
public enum ExportDestination: Equatable, Sendable {
    case file(URL)
    case panel(directory: URL?, notice: String?)
}

extension DocumentController {
    /// With a usable default export folder, the next free name there (` 2`, ` 3`… on collisions). Otherwise a save
    /// panel at Pictures (with a notice when the folder setting exists but can't be used).
    public func exportDestination(now: Date = Date()) -> ExportDestination {
        let fileManager = FileManager.default
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard let folder = settings.exportFolder else { return .panel(directory: pictures, notice: nil) }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
            fileManager.isWritableFile(atPath: folder.path)
        else { return .panel(directory: pictures, notice: UIStrings.exportFolderUnavailable) }
        let name = ExportFileNaming.uniqueName(model.suggestedExportName(now: now)) {
            fileManager.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return .file(folder.appendingPathComponent(name))
    }
}

// MARK: Menus

extension DocumentController {
    /// Menu validation: actions that need content are disabled on an empty document.
    public func isEnabled(_ command: MenuCommand) -> Bool {
        switch command {
        case .exportImage: model.canExport
        case .exportVideo: model.canExportVideo
        case .animate: model.canAnimate
        case .copy, .clearContent, .save: model.hasContent
        case .crop: model.canCrop
        case .captureArea, .captureWindow: !model.capture.isCapturingScreen
        case .captureWebsite: !model.capture.isCapturingWebsite
        case .startOver: model.session.canStartOver(to: defaultTemplateDocument)
        case .undo: model.canUndo
        case .redo: model.canRedo
        default: true
        }
    }

    /// Titles that follow state ("Undo Change Corner Style", "Hide Inspector").
    public func menuTitle(_ command: MenuCommand) -> String {
        switch command {
        case .undo: model.undoTitle
        case .redo: model.redoTitle
        case .toggleInspector: model.showsInspector ? UIStrings.hideInspector : UIStrings.showInspector
        case .animate: model.animate.isActive ? UIStrings.exitAnimate : UIStrings.animate
        default: MenuCatalog.title(command)
        }
    }
}
