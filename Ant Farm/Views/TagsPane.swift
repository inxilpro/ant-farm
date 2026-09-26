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
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterField(prompt: "Filter tags", text: $filter)
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
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
