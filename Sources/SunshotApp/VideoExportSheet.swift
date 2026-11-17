import AppKit
import SunshotCore
import SunshotPlatform
import SunshotRender
import SwiftUI

/// Export Video…: resolution, frame rate and codec, read-only resolution / duration / format, and a progress bar
/// with Cancel Render while the movie is written.
struct VideoExportSheet: View {
    let model: EditorModel

    private var options: VideoExportOptions { model.videoOptions }
    private var animate: AnimateState { model.animate }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(UIStrings.exportVideoTitle).font(.title3.weight(.semibold))
            Form {
                Picker(UIStrings.resolutionPicker, selection: binding(\.resolution)) {
                    ForEach(VideoResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker(UIStrings.frameRatePicker, selection: binding(\.frameRate)) {
                    ForEach(VideoFrameRate.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker(UIStrings.codecPicker, selection: binding(\.codec)) {
                    ForEach(VideoCodec.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!model.isVideoCodecSelectable)
                LabeledContent(UIStrings.resolutionRow, value: model.videoResolutionText)
                LabeledContent(UIStrings.durationRow, value: model.videoDurationText)
                LabeledContent(UIStrings.formatRow, value: model.videoFormatText)
            }
            .formStyle(.grouped)
            .disabled(animate.isExporting)
            if !model.isVideoCodecSelectable {
                Text(UIStrings.transparentVideoHint).font(.callout).foregroundStyle(.secondary)
            }
            if animate.isExporting {
                ProgressView(value: animate.exportProgress) { Text(UIStrings.rendering) }
            }
            HStack {
                Spacer()
                if animate.isExporting {
                    Button(UIStrings.cancelRender, role: .cancel) { model.cancelVideoExport() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(UIStrings.cancel, role: .cancel) { animate.showsExportSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button(UIStrings.exportNow) { Task { await VideoPanels.export(model) } }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canExportVideo)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VideoExportOptions, Value>) -> Binding<Value> {
        Binding(
            get: { options[keyPath: keyPath] }, set: { value in model.setVideoOptions { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Open and save panels for video (AppKit).
@MainActor
enum VideoPanels {
    static func importVideo(into model: EditorModel) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoLoader.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.importVideo(at: url)
    }

    static func export(_ model: EditorModel) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [model.videoContentType]
        panel.nameFieldStringValue = model.suggestedVideoName()
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.exportVideo(to: url)
    }
}
