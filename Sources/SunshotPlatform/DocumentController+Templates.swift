public import SunshotCore
public import SunshotRender

/// S12: Settings ▸ Default template — the template new documents, Start Over and launch use.
extension DocumentController {
    /// The chosen default template (the plain "Screenshot" one when the setting names nothing known).
    public var defaultTemplate: DocumentTemplate? {
        model.templates.library.template(matching: settings.defaultTemplate)
    }

    /// The empty document File ▸ New and Start Over produce: S16's saved default style when there is one, else the
    /// default template.
    public var defaultTemplateDocument: EditorDocument {
        if let quickStyle { return EditorDocument(project: quickStyle.project) }
        return EditorSession.document(for: defaultTemplate)
    }

    /// The id the Settings picker shows for the stored value (S7 stored the name "Screenshot").
    public var defaultTemplateID: String {
        get { defaultTemplate?.id ?? TemplateCatalog.defaultID }
        set { settings.defaultTemplate = newValue }
    }

    /// At launch the empty window starts in the default template (nothing to save until content arrives).
    func openDefaultTemplateAtLaunch() {
        guard fileURL == nil, model.session.document == EditorSession.defaultDocument,
            model.session.history.canUndo == false
        else { return }
        let document = defaultTemplateDocument
        guard document != model.session.document else { return }
        model.session = EditorSession(document: document)
        savedDocument = document
    }
}
