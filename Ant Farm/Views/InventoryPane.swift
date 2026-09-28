//
//  InventoryPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// The sidebar: the folder, the groups and hosts to limit the run to, then the playbook
/// and inventory to run with.
struct InventoryPane: View {
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Bindable var workspace: Workspace
    @State private var filter = ""
    /// Groups the user has folded away. Groups start out expanded.
    @State private var collapsed = Set<[String]>()
    @SceneStorage("showsGroups") private var showsGroups = true
    @SceneStorage("showsHosts") private var showsHosts = true

    var body: some View {
        List {
            if app.tools != nil {
                content
            }
        }
        .listStyle(.sidebar)
        .overlay { overlay }
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                FolderHeader(workspace: workspace)
                FilterField(prompt: "Filter hosts", target: .hosts, text: $filter)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                SelectionSummary(emptyText: "Runs on all hosts", selection: workspace.limit) {
                    workspace.changeSelections("Clear Hosts", undoManager: undoManager) { $0.limit.removeAll() }
                }
                PlaybookPickers(workspace: workspace)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
    }

    @ViewBuilder
    private var content: some View {
        let tree = workspace.contents.groupTree(including: matches)
        let hosts = workspace.contents.hosts.filter(matches)

        if !tree.isEmpty {
            Section("Groups", isExpanded: expanded($showsGroups)) {
                ForEach(tree) { node in
                    GroupTreeRow(node: node, workspace: workspace, collapsed: $collapsed, expandAll: !filter.isEmpty)
                }
            }
        }
        if !hosts.isEmpty {
            Section("Hosts", isExpanded: expanded($showsHosts)) {
                ForEach(hosts, id: \.self) { host in
                    SelectionRow(
                        title: host,
                        systemImage: "desktopcomputer",
                        state: workspace.limit.state(of: host),
                        inheritedState: workspace.contents.coveringState(ofHost: host, in: workspace.limit)
                    ) { state in
                        workspace.changeSelections(state.actionName, undoManager: undoManager) { $0.limit.set(host, to: state) }
                    }
                }
            }
        }
    }

    /// While filtering, a section shows its matches even if it's collapsed.
    private func expanded(_ isExpanded: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { isExpanded.wrappedValue || !filter.isEmpty },
            set: { isExpanded.wrappedValue = $0 }
        )
    }

    @ViewBuilder
    private var overlay: some View {
        if app.tools == nil && !app.isLocatingTools {
            AnsibleMissingView()
        } else if workspace.isLoadingInventory || app.isLocatingTools {
            ProgressView()
        } else if let error = workspace.inventoryError {
            ContentUnavailableView {
                Label("Couldn't Load Inventory", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).textSelection(.enabled)
            } actions: {
                Button("Try Again") { Task { await workspace.loadInventoryContents() } }
            }
        } else if !filter.isEmpty && workspace.contents.hosts.filter(matches).isEmpty
                    && workspace.contents.groupTree(including: matches).isEmpty {
            ContentUnavailableView.search(text: filter)
        }
    }

    private func matches(_ name: String) -> Bool {
        filter.isEmpty || name.localizedCaseInsensitiveContains(filter)
    }
}

/// A group and, beneath it, the groups it contains.
private struct GroupTreeRow: View {
    @Environment(\.undoManager) private var undoManager
    let node: InventoryGroupNode
    let workspace: Workspace
    @Binding var collapsed: Set<[String]>
    /// While filtering, show every match instead of honoring folded groups.
    let expandAll: Bool
    /// An included or excluded group above this one, which covers it.
    var inheritedState: SelectionState?

    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    GroupTreeRow(node: child, workspace: workspace, collapsed: $collapsed, expandAll: expandAll, inheritedState: coveringState)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        let group = node.group
        return SelectionRow(
            title: group.name,
            subtitle: "\(group.hosts.count)",
            systemImage: "square.stack.3d.up",
            help: group.hosts.joined(separator: ", "),
            state: workspace.limit.state(of: group.name),
            inheritedState: inheritedState
        ) { state in
            workspace.changeSelections(state.actionName, undoManager: undoManager) { workspace in
                workspace.limit.set(group.name, to: state)
                // The group now covers its subgroups and hosts, so they start over unchecked when it's cleared.
                if state != .none {
                    for name in workspace.contents.subgroups(of: group.name).union(group.hosts) {
                        workspace.limit.set(name, to: .none)
                    }
                }
            }
        }
    }

    /// The state this group passes down to its subgroups.
    private var coveringState: SelectionState? {
        if let inheritedState { return inheritedState }
        let own = workspace.limit.state(of: node.group.name)
        return own == .none ? nil : own
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandAll || !collapsed.contains(node.id) },
            set: { expanded in
                if expanded {
                    collapsed.remove(node.id)
                } else {
                    collapsed.insert(node.id)
                }
            }
        )
    }
}

/// The folder the rest of the window works on.
private struct FolderHeader: View {
    let workspace: Workspace

    var body: some View {
        Menu {
            FolderMenuItems()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(workspace.directory.path.abbreviatingHome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Open another folder")
    }
}

/// The playbook and inventory to run with, full width and without labels.
private struct PlaybookPickers: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(spacing: 6) {
            Picker("Playbook", selection: $workspace.selectedPlaybookPath) {
                if workspace.playbooks.isEmpty {
                    Text("No Playbooks").tag(String?.none)
                }
                ForEach(workspace.playbooks) { playbook in
                    Label(playbook.path, systemImage: "doc.text").tag(Optional(playbook.path))
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(workspace.playbooks.isEmpty)
            .help(workspace.selectedPlaybook.map { "Playbook: " + ($0.name ?? $0.path) } ?? "Playbook")

            Picker("Inventory", selection: $workspace.selectedInventoryID) {
                ForEach(workspace.inventories) { source in
                    Label(source.label, systemImage: "server.rack").tag(Optional(source.id))
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(workspace.inventories.count < 2)
            .help("Inventory: " + (workspace.selectedInventory?.hint ?? workspace.selectedInventory?.label ?? "Ansible default"))
        }
        .labelsHidden()
        .buttonSizing(.flexible)
    }
}

struct AnsibleMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Ansible Not Found", systemImage: "questionmark.folder")
        } description: {
            Text("Ant Farm couldn't find ansible-playbook. Install Ansible (for example with `brew install ansible`) or set its folder in Settings.")
        } actions: {
            SettingsLink { Text("Open Settings…") }
        }
    }
}
