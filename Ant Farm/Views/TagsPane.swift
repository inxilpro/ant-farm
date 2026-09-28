//
//  TagsPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// Second pane: pick the tags to run (or skip) in the selected playbook.
struct TagsPane: View {
    @Environment(\.undoManager) private var undoManager
    @Bindable var workspace: Workspace
    @State private var filter = ""

    var body: some View {
        let tags = workspace.tags.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }

        List {
            ForEach(tags, id: \.self) { tag in
                SelectionRow(
                    title: tag,
                    systemImage: tag == "always" || tag == "never" ? "tag.slash" : "tag",
                    state: workspace.tagSelection.state(of: tag)
                ) { state in
                    workspace.changeSelections(state.actionName, undoManager: undoManager) { $0.tagSelection.set(tag, to: state) }
                }
            }
        }
        .overlay { overlay(filteredEmpty: tags.isEmpty) }
        .safeAreaBar(edge: .top, spacing: 0) {
            FilterField(prompt: "Filter tags", target: .tags, text: $filter)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SelectionSummary(emptyText: "Runs all tags", selection: workspace.tagSelection) {
                    workspace.changeSelections("Clear Tags", undoManager: undoManager) { $0.tagSelection.removeAll() }
                }
                TextField("Extra arguments", text: $workspace.extraArguments, prompt: Text("Extra arguments, e.g. -e env=staging"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .help("Passed to ansible-playbook as-is, e.g. --ask-become-pass or -e key=value")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: TagColumn.idealWidth(for: workspace.tags) ?? 220)
        // The column is laid out before the tags load, so widen it once they arrive.
        .background(ColumnWidener(width: TagColumn.idealWidth(for: workspace.tags)))
    }


    @ViewBuilder
    private func overlay(filteredEmpty: Bool) -> some View {
        if workspace.selectedPlaybook == nil && !workspace.isDiscovering {
            ContentUnavailableView(
                "No Playbooks",
                systemImage: "doc.questionmark",
                description: Text("Ant Farm looks for playbooks in this folder and in ./playbooks.")
            )
        } else if workspace.isLoadingTags {
            ProgressView()
        } else if let error = workspace.tagsError {
            ContentUnavailableView {
                Label("Couldn't List Tags", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await workspace.loadTags() } }
            }
        } else if workspace.tags.isEmpty && workspace.selectedPlaybook != nil {
            ContentUnavailableView(
                "No Tags",
                systemImage: "tag",
                description: Text("This playbook doesn't use tags. Every task will run.")
            )
        } else if filteredEmpty {
            ContentUnavailableView.search(text: filter)
        }
    }
}

/// Sizes the tags column to its tags.
enum TagColumn {
    /// The row's circle, tag icon, padding, and scroller.
    private static let chrome: CGFloat = 96

    /// Wide enough for nine in ten tags, so one or two long ones don't widen the column much.
    static func idealWidth(for tags: [String]) -> CGFloat? {
        guard !tags.isEmpty else { return nil }
        let font = NSFont.preferredFont(forTextStyle: .body)
        let widths = tags.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.sorted()
        let fit = widths[Int(Double(widths.count - 1) * 0.9)]
        return min(max(fit + chrome, 180), 360).rounded(.up)
    }
}

/// Widens the split view column it sits in to `width`, if it's narrower, once the tags load.
///
/// SwiftUI only offers an ideal column width, which it applies before the tags load and
/// which the split view's saved width then overrides.
private struct ColumnWidener: NSViewRepresentable {
    let width: CGFloat?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let width, !context.coordinator.didStart else { return }
        context.coordinator.didStart = true
        Task { @MainActor in
            // The view may not be in the window yet, and the split view restores its saved
            // widths after the first layout, so keep the column wide for a moment.
            for _ in 0..<30 {
                Self.widen(columnOf: view, to: width)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func widen(columnOf view: NSView, to width: CGFloat) {
        var ancestor = view.superview
        while let current = ancestor, !(current is NSSplitView) {
            ancestor = current.superview
        }
        guard let splitView = ancestor as? NSSplitView else { return }
        let columns = splitView.arrangedSubviews
        guard let index = columns.firstIndex(where: { view.isDescendant(of: $0) }),
              index < columns.count - 1 else { return }
        // A column's view reaches under the floating sidebar, so measure only what shows.
        let leading = index > 0 && !splitView.isSubviewCollapsed(columns[index - 1]) ? columns[index - 1].frame.maxX : columns[index].frame.minX
        let visible = columns[index].frame.maxX - leading
        if visible > 0 && visible < width {
            splitView.setPosition(columns[index].frame.maxX + width - visible, ofDividerAt: index)
        }
    }

    final class Coordinator {
        var didStart = false
    }
}
