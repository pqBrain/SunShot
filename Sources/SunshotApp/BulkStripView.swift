import SunshotCore
import SunshotPlatform
import SwiftUI

/// S14 preview strip under the editor: one thumbnail per batch item (all in the shared style), Export All, and
/// the export progress / summary. Shown only while a batch is open.
struct BulkStripView: View {
    @Bindable var bulk: BulkSession

    var body: some View {
        if bulk.isActive {
            VStack(alignment: .leading, spacing: 8) {
                header
                if let progress = bulk.progress {
                    BulkProgressRow(progress: progress) { bulk.cancelExport() }
                } else if let report = bulk.report {
                    BulkSummaryRow(report: report, reveal: { bulk.revealExported() }, dismiss: { bulk.dismissReport() })
                }
                thumbnails
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding([.horizontal, .bottom], 12)
            .task(id: bulk.editor.project) {
                // Debounced: a slider drag changes the project on every tick; render once it settles.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await bulk.refreshThumbnails()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(UIStrings.imageCount(bulk.items.count)).font(.headline)
            Text(UIStrings.sharedStyleHint).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button(UIStrings.exportAll) { Task { await BulkPanels.exportAll(from: bulk) } }
                .buttonStyle(.glassProminent)
                .disabled(!bulk.canExportAll)
                .accessibilityLabel(UIStrings.exportAllAccessibility)
            Button {
                bulk.close()
            } label: {
                Label(UIStrings.closeBatch, systemImage: "xmark").labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .help(UIStrings.closeBatch)
            .disabled(bulk.isExporting)
        }
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(bulk.items.enumerated()), id: \.element.id) { index, item in
                        BulkThumbnail(bulk: bulk, item: item, index: index).id(item.id)
                    }
                }
                .padding(4)
            }
            .frame(height: 128)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.rightArrow) { move(1) }
            .onKeyPress(.delete) {
                Task { await bulk.removeSelected() }
                return .handled
            }
            .onChange(of: bulk.selectedID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .accessibilityLabel(UIStrings.batchStripAccessibility)
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        Task { await bulk.selectAdjacent(offset) }
        return .handled
    }
}

/// One strip tile: the thumbnail (or a spinner / error badge), name, selection ring, reorder by drag.
struct BulkThumbnail: View {
    let bulk: BulkSession
    let item: BulkItem
    let index: Int

    private var isSelected: Bool { bulk.selectedID == item.id }
    private var error: String? { bulk.itemErrors[item.id] }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let error {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .help(error)
                } else if let thumbnail = bulk.thumbnails[item.id] {
                    Image(decorative: thumbnail, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 120, height: 96)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            Text(item.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 120)
        }
        .contentShape(.rect)
        .onTapGesture { Task { await bulk.select(item.id) } }
        .draggable(item.id.uuidString)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            bulk.move(id, onto: item.id)
            return true
        }
        .contextMenu {
            Button(UIStrings.moveLeft) { bulk.nudge(item.id, by: -1) }.disabled(index == 0)
            Button(UIStrings.moveRight) { bulk.nudge(item.id, by: 1) }.disabled(index == bulk.items.count - 1)
            Divider()
            Button(UIStrings.removeFromBatch) { Task { await bulk.remove(item.id) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            UIStrings.batchItemLabel(
                name: item.displayName, index: index, count: bulk.items.count, isSelected: isSelected,
                hasError: error != nil)
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { Task { await bulk.select(item.id) } }
    }
}

struct BulkProgressRow: View {
    let progress: BulkProgress
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress.fractionCompleted) {
                Text(UIStrings.exportingProgress(progress)).font(.callout)
            }
            Button(UIStrings.cancel, action: cancel).keyboardShortcut(.cancelAction)
        }
    }
}

struct BulkSummaryRow: View {
    let report: BulkReport
    let reveal: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Label(
                    UIStrings.exportSummary(report),
                    systemImage: report.isCompleteSuccess ? "checkmark.circle" : "exclamationmark.circle")
                Spacer()
                if !report.written.isEmpty { Button(UIStrings.showInFinder, action: reveal) }
                Button(UIStrings.done, action: dismiss)
            }
            ForEach(report.failures.prefix(5)) { failure in
                Text(UIStrings.failureLine(failure)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
