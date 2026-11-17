extension Project {
    /// The document's annotations. Setting an empty layer stores nothing, so "no annotations" has one representation.
    public var annotations: AnnotationLayer {
        get { annotationLayer ?? AnnotationLayer() }
        set { annotationLayer = newValue == AnnotationLayer() ? nil : newValue }
    }
}
