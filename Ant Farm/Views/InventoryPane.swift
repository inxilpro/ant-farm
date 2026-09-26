//
//  InventoryPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// The sidebar: the folder, the playbook and inventory to run with, then the groups
/// and hosts to limit the run to.
struct InventoryPane: View {
    @Environment(AppState.self) private var app
    @Bindable var workspace: Workspace
    @State private var filter = ""
    /// Groups the user has folded away. Groups start out expanded.
    @State private var collapsed = Set<[String]>()

    var body: some View {
        List {
            if app.tools != nil {
                content
            }
        }
        .listStyle(.sidebar)
        .overlay { overlay }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                SidebarHeader(workspace: workspace)
                FilterField(prompt: "Filter hosts", text: $filter)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionSummary(emptyText: "Runs on all hosts", selection: workspace.limit) {
                workspace.limit.removeAll()
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
            Section("Groups") {
                ForEach(tree) { node in
                    GroupTreeRow(node: node, workspace: workspace, collapsed: $collapsed, expandAll: !filter.isEmpty)
                }
            }
        }
        if !hosts.isEmpty {
            Section("Hosts") {
                ForEach(hosts, id: \.self) { host in
                    SelectionRow(
                        title: host,
                        systemImage: "desktopcomputer",
                        state: workspace.limit.state(of: host)
                    ) { workspace.limit.set(host, to: $0) }
                }
            }
        }
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
    let node: InventoryGroupNode
    let workspace: Workspace
    @Binding var collapsed: Set<[String]>
    /// While filtering, show every match instead of honoring folded groups.
    let expandAll: Bool

    var body: some View {
        if node.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    GroupTreeRow(node: child, workspace: workspace, collapsed: $collapsed, expandAll: expandAll)
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
            state: workspace.limit.state(of: group.name)
        ) { workspace.limit.set(group.name, to: $0) }
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

/// The folder, playbook, and inventory: what the rest of the window works on.
private struct SidebarHeader: View {
    @Bindable var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Playbook")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Picker("Playbook", selection: $workspace.selectedPlaybookPath) {
                        if workspace.playbooks.isEmpty {
                            Text("None").tag(String?.none)
                        }
                        ForEach(workspace.playbooks) { playbook in
                            Text(playbook.path).tag(Optional(playbook.path))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(workspace.playbooks.isEmpty)
                    .help(workspace.selectedPlaybook?.name ?? "Playbook")
                }
                GridRow {
                    Text("Inventory")
                        .foregroundStyle(.secondary)
                    Picker("Inventory", selection: $workspace.selectedInventoryID) {
                        ForEach(workspace.inventories) { source in
                            Text(source.label).tag(Optional(source.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(workspace.inventories.count < 2)
                    .help(workspace.selectedInventory?.hint ?? workspace.selectedInventory?.label ?? "Inventory")
                }
            }
            .font(.callout)
        }
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
