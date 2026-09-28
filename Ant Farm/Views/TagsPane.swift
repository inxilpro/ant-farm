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
        .frame(minWidth: 180, idealWidth: TagColumn.idealWidth(for: workspace.tags) ?? 220, maxWidth: 480)
        .background(PaneSizer(idealWidth: TagColumn.idealWidth(for: workspace.tags)))
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

/// Restores the tags pane to the width it was last dragged to, or, until it has been
/// dragged, widens it to `idealWidth` once the tags load.
///
/// SwiftUI's split view neither remembers its panes' widths nor applies an ideal width
/// that arrives after its first layout, when the tags load.
private struct PaneSizer: NSViewRepresentable {
    let idealWidth: CGFloat?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.idealWidth = idealWidth
        guard !coordinator.didStart else { return }
        coordinator.didStart = true
        Task { @MainActor in
            // The view may not be in the window yet, and the split view lays its panes out
            // again after it appears, so keep sizing the pane for a moment.
            for _ in 0..<30 {
                coordinator.size(paneOf: view)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        var didStart = false
        var idealWidth: CGFloat?
        private var observer: NSObjectProtocol?
        /// Set while this code moves the divider, so only the user's drags are saved.
        private var isSizing = false

        private var savedWidth: CGFloat? {
            let width = UserDefaults.standard.double(forKey: SettingsKey.tagsPaneWidth)
            return width > 0 ? width : nil
        }

        func size(paneOf view: NSView) {
            var ancestor = view.superview
            while let current = ancestor, !(current is NSSplitView) {
                ancestor = current.superview
            }
            guard let splitView = ancestor as? NSSplitView,
                  let pane = splitView.arrangedSubviews.first,
                  view.isDescendant(of: pane) else { return }
            observe(splitView)

            let current = pane.frame.width
            let target: CGFloat
            if let saved = savedWidth {
                target = saved
            } else if let ideal = idealWidth, current < ideal {
                target = ideal
            } else {
                return
            }
            guard abs(current - target) >= 1 else { return }
            isSizing = true
            splitView.setPosition(pane.frame.minX + target, ofDividerAt: 0)
            isSizing = false
        }

        private func observe(_ splitView: NSSplitView) {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: splitView,
                queue: .main
            ) { [weak self, weak splitView] note in
                // Resizing the window resizes the panes too, but without a divider index.
                guard note.userInfo?["NSSplitViewDividerIndex"] != nil else { return }
                MainActor.assumeIsolated {
                    guard let self, !self.isSizing, let pane = splitView?.arrangedSubviews.first else { return }
                    UserDefaults.standard.set(Double(pane.frame.width), forKey: SettingsKey.tagsPaneWidth)
                }
            }
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
