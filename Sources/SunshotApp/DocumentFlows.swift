import AppKit
import Observation
import SunshotCore
import SunshotPlatform
import SunshotRender
import UniformTypeIdentifiers

/// File-menu flows that need panels or alerts. Decisions live in `DocumentController`; this only asks the user.
@MainActor
enum DocumentFlows {
    static let documentType = UTType(exportedAs: DocumentPackage.typeIdentifier, conformingTo: .package)

    /// Runs the close prompt when needed. Returns false when the user cancelled.
    static func closeCurrent(_ controller: DocumentController) async -> Bool {
        guard controller.needsSavePrompt else {
            await controller.close(discardChanges: controller.discardsWithoutAsking)
            return true
        }
        let alert = NSAlert()
        alert.messageText = UIStrings.saveChangesTitle(controller.displayName)
        alert.informativeText = UIStrings.saveChangesMessage
        alert.addButton(withTitle: UIStrings.save)
        alert.addButton(withTitle: UIStrings.cancel)
        alert.addButton(withTitle: UIStrings.dontSave)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = UIStrings.dontAskAgain
        let response = alert.runModal()
        // "Don't ask again" remembers Don't Save; Settings turns the prompt back on.
        if response == .alertThirdButtonReturn, alert.suppressionButton?.state == .on {
            controller.settings.askToSaveOnClose = false
        }
        switch response {
        case .alertFirstButtonReturn:
            guard await saveAs(controller) else { return false }
            await controller.close(discardChanges: false)
            return true
        case .alertThirdButtonReturn:
            await controller.close(discardChanges: true)
            return true
        default:
            return false
        }
    }

    static func newDocument(_ controller: DocumentController) async {
        guard await closeCurrent(controller) else { return }
        await controller.newDocument()
    }

    /// Open…: a `.sunshot` document replaces the current one; an image becomes the content.
    static func open(_ controller: DocumentController) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [documentType] + ImageTypes.supported
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await open(url, in: controller)
    }

    static func open(_ url: URL, in controller: DocumentController) async {
        guard url.pathExtension == DocumentPackage.fileExtension else {
            await controller.model.importFile(at: url)
            return
        }
        guard await closeCurrent(controller) else { return }
        if await controller.openDocument(at: url) { return }
        await offerPlaceholders(controller)
    }

    static func openRecent(_ item: RecentDocument, in controller: DocumentController) async {
        guard await closeCurrent(controller) else { return }
        if await controller.openRecent(item) { return }
        await offerPlaceholders(controller)
    }

    private static func offerPlaceholders(_ controller: DocumentController) async {
        guard let offer = controller.placeholderOffer else { return }
        controller.placeholderOffer = nil
        let alert = NSAlert()
        alert.messageText = UIStrings.documentOpenFailed
        alert.informativeText = offer.message
        alert.addButton(withTitle: UIStrings.openWithPlaceholders)
        alert.addButton(withTitle: UIStrings.cancel)
        if alert.runModal() == .alertFirstButtonReturn {
            await controller.openDocument(at: offer.url, allowPlaceholders: true)
        }
    }

    /// ⌘S: in place when the document has a file, else Save As.
    static func save(_ controller: DocumentController) async {
        if await controller.save() { return }
        _ = await saveAs(controller)
    }

    @discardableResult
    static func saveAs(_ controller: DocumentController) async -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [documentType]
        panel.nameFieldStringValue = "\(controller.displayName).\(DocumentPackage.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return await controller.saveAs(to: url)
    }

    /// ⇧⌘E: straight into the default export folder when set and usable, else the save panel.
    static func export(_ controller: DocumentController) async {
        let model = controller.model
        guard model.canExport else { return }
        switch controller.exportDestination() {
        case .file(let url):
            await model.export(to: url)
            if model.alert == nil { model.notice = UIStrings.exportedTo(url.lastPathComponent) }
        case .panel(let directory, let notice):
            if let notice { model.notice = notice }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [model.exportContentType]
            panel.nameFieldStringValue = model.suggestedExportName()
            panel.directoryURL = directory
            guard panel.runModal() == .OK, let url = panel.url else { return }
            await model.export(to: url)
        }
    }

    /// File ▸ Start Over (and the toolbar broom): asks first when "Confirm before resetting" is on.
    static func startOver(_ controller: DocumentController) {
        guard controller.model.session.canStartOver else { return }
        if controller.startOverNeedsConfirmation {
            let alert = NSAlert()
            alert.messageText = UIStrings.startOverTitle
            alert.informativeText = UIStrings.startOverMessage
            let confirm = alert.addButton(withTitle: UIStrings.startOverButton)
            confirm.hasDestructiveAction = true
            alert.addButton(withTitle: UIStrings.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        controller.startOver()
    }
}

/// Quit, resign-active autosave and Finder "Open With".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DocumentController()
    /// S14 batch: shares the editor's style; lives as long as the app.
    lazy var bulk = BulkSession(editor: controller.model)
    /// S10: optional global Capture Area shortcut (off by default).
    let hotkey = GlobalCaptureHotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.settings.appearance.apply(to: NSApplication.shared)
        Task { await controller.recoverDraft() }
        observeSettings()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated { self?.windowWillClose(closing) }
        }
    }

    /// S16: with the menu bar icon shown, closing the window leaves Sunshot running there (no Dock icon).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !controller.settings.showsMenuBarIcon
    }

    private func windowWillClose(_ window: NSWindow?) {
        guard let window, window.identifier?.rawValue.contains(Studio.windowID) == true,
            controller.settings.showsMenuBarIcon
        else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// The global shortcut lives here, not on the window, so it works while the window is closed. Re-registered
    /// whenever Settings change.
    private func observeSettings() {
        let settings = withObservationTracking {
            controller.settings
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
        let controller = controller
        hotkey.configure(settings.captureHotkeyEnabled ? settings.captureShortcut : nil) {
            AreaCapture.start(controller: controller, destination: controller.settings.globalCaptureDestination)
        }
        // Hiding the icon while the window is closed would leave no way back: bring the studio forward.
        if !settings.showsMenuBarIcon, !NSApp.windows.contains(where: Studio.isStudio),
            NSApp.activationPolicy() == .accessory
        {
            Studio.show(controller)
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        Task { await controller.autosave() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { await DocumentFlows.open(url, in: controller) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let proceed = await DocumentFlows.closeCurrent(controller)
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}
