import AppKit
public import Foundation
public import Observation
public import SunshotCore
public import SunshotRender
import os

/// Where Sunshot keeps its own files (inside the sandbox container when sandboxed).
public struct DocumentLocations: Sendable {
    public var drafts: URL
    public var themes: URL

    public init(drafts: URL, themes: URL) {
        self.drafts = drafts
        self.themes = themes
    }

    /// `~/Library/Application Support/Sunshot/{Drafts,Themes}`.
    public static func standard() -> DocumentLocations {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("Sunshot", isDirectory: true)
        return DocumentLocations(
            drafts: root.appendingPathComponent("Drafts", isDirectory: true),
            themes: root.appendingPathComponent("Themes", isDirectory: true))
    }
}

/// "Open with placeholders?" offer after a document with missing media failed to open.
public struct PlaceholderOffer: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let url: URL
    public let message: String
}

/// Writes packages off the main actor, one at a time.
actor DocumentWriter {
    /// Test hook: called on every write with whether it ran on the main thread.
    var onWrite: (@Sendable (Bool) -> Void)?

    func setOnWrite(_ hook: (@Sendable (Bool) -> Void)?) { onWrite = hook }

    func write(_ document: EditorDocument, to url: URL) throws {
        onWrite?(Thread.isMainThread)
        try DocumentPackage.write(document, to: url)
    }
}

/// The open document's file, autosave, drafts, Open Recent, themes and settings. The document itself lives in
/// `model.session` (the single undoable store); this class only decides where and when it is written.
@MainActor
@Observable
public final class DocumentController {
    public let model: EditorModel
    public let locations: DocumentLocations
    /// The saved file, or nil for an untitled document (autosaved to `draftURL`).
    public private(set) var fileURL: URL?
    public private(set) var draftURL: URL
    /// Opened from a newer schema: never written in place.
    public private(set) var isReadOnly = false
    /// The document as last written (or opened); changes since then make it dirty.
    public internal(set) var savedDocument: EditorDocument
    public internal(set) var themes: [Theme] = []
    public private(set) var recents: RecentList<RecentDocument>
    public var placeholderOffer: PlaceholderOffer?
    public var settings: AppSettings {
        didSet { settingsChanged() }
    }

    let autosaveDelay: Duration
    let writer = DocumentWriter()
    let settingsStore: SettingsStore
    let recentsStore: RecentDocumentsStore
    let themeStore: ThemeStore
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var accessedURL: URL?
    static let log = Logger(subsystem: "app.sunshot", category: "documents")

    public init(
        model: EditorModel = EditorModel(), locations: DocumentLocations = .standard(),
        defaults: UserDefaults = .standard, autosaveDelay: Duration = .seconds(5)
    ) {
        self.model = model
        self.locations = locations
        self.autosaveDelay = autosaveDelay
        settingsStore = SettingsStore(defaults: defaults)
        recentsStore = RecentDocumentsStore(defaults: defaults)
        themeStore = ThemeStore(directory: locations.themes)
        settings = settingsStore.load()
        recents = recentsStore.load()
        draftURL = Self.newDraftURL(in: locations.drafts)
        savedDocument = model.session.document
        themes = themeStore.load()
        model.filenameTemplate = settings.effectiveFilenameTemplate
        openDefaultTemplateAtLaunch()
        observeDocument()
    }

    // MARK: State

    public var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? UIStrings.untitled
    }

    public var isDirty: Bool { model.session.document != savedDocument }

    /// Closing asks "Save changes to Untitled?" only for never-saved documents with content (and for read-only
    /// documents that were changed); everything else is saved silently.
    public var needsSavePrompt: Bool {
        model.hasContent && (fileURL == nil || (isReadOnly && isDirty))
    }

    // MARK: New, open, save

    /// A fresh untitled document from the default template. Call after `close(discardChanges:)`.
    public func newDocument() async {
        await replaceDocument(with: defaultTemplateDocument, fileURL: nil, readOnly: false)
        draftURL = Self.newDraftURL(in: locations.drafts)
    }

    /// Opens a `.sunshot` package. Failures show "Can't open this document" (missing media offers placeholders).
    @discardableResult
    public func openDocument(at url: URL, allowPlaceholders: Bool = false) async -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try DocumentPackage.read(from: url, allowPlaceholders: allowPlaceholders)
            }.value
            await replaceDocument(with: loaded.document, fileURL: url, readOnly: loaded.isReadOnly)
            draftURL = Self.newDraftURL(in: locations.drafts)
            if accessing { accessedURL = url }
            if loaded.isReadOnly {
                model.notice = DocumentManifestCodec.newerVersionMessage
            } else if !loaded.placeholders.isEmpty {
                model.notice = UIStrings.placeholdersUsed
            }
            noteRecent(url)
            return true
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            let reason = (error as? DocumentFormatError)?.reason ?? error.localizedDescription
            let message = "\(url.lastPathComponent): \(reason)"
            if case DocumentFormatError.missingMedia = error, !allowPlaceholders {
                placeholderOffer = PlaceholderOffer(url: url, message: message)
            } else {
                model.alert = AlertContent(title: UIStrings.documentOpenFailed, message: message)
            }
            return false
        }
    }

    /// Opens an item of File ▸ Open Recent; a deleted file is removed from the list with "File not found".
    @discardableResult
    public func openRecent(_ item: RecentDocument) async -> Bool {
        let url = BookmarkedURL.resolve(bookmark: item.bookmark, path: item.url.path) ?? item.url
        guard FileManager.default.fileExists(atPath: url.path) else {
            recents.remove { $0.id == item.id }
            recentsStore.save(recents)
            model.alert = AlertContent(title: UIStrings.fileNotFound, message: item.url.path)
            return false
        }
        return await openDocument(at: url)
    }

    public func clearRecents() {
        recents.clear()
        recentsStore.save(recents)
    }

    /// ⌘S: writes in place. Returns false when the document needs a location first (show Save As).
    @discardableResult
    public func save() async -> Bool {
        guard let fileURL, !isReadOnly else { return false }
        return await write(to: fileURL)
    }

    /// Save As: writes to `url`, which becomes the document's file; the untitled draft is removed.
    @discardableResult
    public func saveAs(to url: URL) async -> Bool {
        guard await write(to: url) else { return false }
        if fileURL == nil { removeDraft() }
        fileURL = url
        isReadOnly = false
        noteRecent(url)
        return true
    }

    /// Final step of Close, New, Open and Quit (after any prompt): saved documents get a last save; an untitled
    /// draft is kept only if it has content and the user didn't choose Don't Save.
    public func close(discardChanges: Bool) async {
        autosaveTask?.cancel()
        if fileURL == nil {
            if discardChanges || !model.hasContent {
                removeDraft()
            } else {
                await autosave()
            }
        } else if !discardChanges {
            await autosave()
        }
    }

    /// Restores the most recent untitled draft (after a crash or force-quit). Returns whether one was found.
    @discardableResult
    public func recoverDraft() async -> Bool {
        let drafts =
            (try? FileManager.default.contentsOfDirectory(
                at: locations.drafts, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == DocumentPackage.fileExtension } ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let newest = drafts.max(by: { modified($0) < modified($1) }) else { return false }
        let loaded = try? await Task.detached(priority: .userInitiated) {
            try DocumentPackage.read(from: newest, allowPlaceholders: true)
        }.value
        guard let loaded else {
            try? FileManager.default.removeItem(at: newest)
            return false
        }
        await replaceDocument(with: loaded.document, fileURL: nil, readOnly: false)
        draftURL = newest
        return true
    }

    // MARK: Helpers

    func replaceDocument(with document: EditorDocument, fileURL: URL?, readOnly: Bool) async {
        autosaveTask?.cancel()
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
            self.accessedURL = nil
        }
        savedDocument = document
        model.session = EditorSession(document: document)
        self.fileURL = fileURL
        isReadOnly = readOnly
        await model.refreshPreview()
    }

    /// Writes the current document to `url` off the main actor; on failure shows an alert.
    func write(to url: URL) async -> Bool {
        let document = model.session.document
        do {
            try await writer.write(document, to: url)
            savedDocument = document
            return true
        } catch {
            Self.log.error("Save failed: \(error.localizedDescription, privacy: .public)")
            model.alert = AlertContent(title: UIStrings.saveFailed, message: error.localizedDescription)
            return false
        }
    }

    func removeDraft() {
        try? FileManager.default.removeItem(at: draftURL)
    }

    func noteRecent(_ url: URL) {
        recents.note(RecentDocument(url: url, bookmark: BookmarkedURL.bookmark(for: url))) {
            $0.url.standardizedFileURL == $1.url.standardizedFileURL
        }
        recentsStore.save(recents)
    }

    static func newDraftURL(in folder: URL) -> URL {
        folder.appendingPathComponent("\(UUID().uuidString).\(DocumentPackage.fileExtension)")
    }

    private func settingsChanged() {
        settingsStore.save(settings)
        model.filenameTemplate = settings.effectiveFilenameTemplate
        if let app = NSApp { settings.appearance.apply(to: app) }
    }
}
