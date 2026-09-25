//
//  InventoryPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// First pane: pick the inventory, then the groups and hosts to limit the run to.
struct InventoryPane: View {
    @Environment(AppState.self) private var app
    @Bindable var workspace: Workspace
    @State private var filter = ""

    var body: some View {
        List {
            if app.tools != nil {
                content
            }
        }
        .listStyle(.sidebar)
        .overlay { overlay }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                if workspace.inventories.count > 1 {
                    Picker("Inventory", selection: $workspace.selectedInventoryID) {
                        ForEach(workspace.inventories) { source in
                            Text(source.label).tag(Optional(source.id))
                        }
                    }
                    .labelsHidden()
                    .help(workspace.selectedInventory?.hint ?? "Inventory")
                } else if let source = workspace.selectedInventory {
                    Label(source.label, systemImage: "server.rack")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(source.hint ?? source.label)
                }
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 260)
    }

    @ViewBuilder
    private var content: some View {
        let groups = workspace.contents.groups.filter { matches($0.name) || $0.hosts.contains(where: matches) }
        let hosts = workspace.contents.hosts.filter(matches)

        if !groups.isEmpty {
            Section("Groups") {
                ForEach(groups) { group in
                    SelectionRow(
                        title: group.name,
                        subtitle: "\(group.hosts.count)",
                        systemImage: "square.stack.3d.up",
                        help: group.hosts.joined(separator: ", "),
                        state: workspace.limit.state(of: group.name)
                    ) { workspace.limit.set(group.name, to: $0) }
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
                    && workspace.contents.groups.filter({ matches($0.name) }).isEmpty {
            ContentUnavailableView.search(text: filter)
        }
    }

    private func matches(_ name: String) -> Bool {
        filter.isEmpty || name.localizedCaseInsensitiveContains(filter)
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
