public import AppKit
public import Observation
public import SunshotCore
import SunshotRender
import os

/// The bundled templates, loaded once. A catalog that fails to load is logged and the gallery shows only the
/// plain new document; the smoke test fails if it is empty.
@MainActor
public final class TemplateLibrary {
    public static let shared = TemplateLibrary()

    public let catalog: TemplateCatalog?
    private static let logger = Logger(subsystem: "app.sunshot", category: "templates")

    public init(load: () throws -> TemplateCatalog = { try TemplateCatalog.load() }) {
        do {
            catalog = try load()
        } catch {
            Self.logger.error("Could not load templates: \(String(describing: error), privacy: .public)")
            catalog = nil
        }
    }

    public var templates: [DocumentTemplate] { catalog?.templates ?? [] }

    /// The template for a Settings value (id, or the S7 name "Screenshot"); nil without a catalog.
    public func template(matching key: String) -> DocumentTemplate? { catalog?.template(matching: key) }
}

/// S12 UI state that isn't part of the document: whether the gallery is open and its live previews.
@MainActor
@Observable
public final class TemplateGalleryState {
    public var isPresented = false
    /// Preview per template id for the current content (empty until rendered).
    public internal(set) var thumbnails: [String: CGImage] = [:]
    /// The running preview render (await it in tests).
    public internal(set) var thumbnailTask: Task<Void, Never>?
    /// Device picker tiles per "model/finish/orientation".
    @ObservationIgnored var deviceTiles: [String: CGImage] = [:]
    /// What `thumbnails` were rendered for (content identity + style), so reopening is instant.
    @ObservationIgnored var thumbnailKey: TemplatePreviewKey?

    public let library: TemplateLibrary

    public init(library: TemplateLibrary = .shared) {
        self.library = library
    }

    public var templates: [DocumentTemplate] { library.templates }
}

/// Everything a template preview depends on: the content and what a template keeps (annotations, title).
struct TemplatePreviewKey: Hashable {
    let content: UUID?
    let snippet: CodeSnippet?
    let annotations: AnnotationLayer?
    let title: String
    let media: [String]
}
