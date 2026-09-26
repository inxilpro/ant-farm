//
//  WorkspaceView.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// The three-pane window for an open workspace. The sidebar holds the folder, hosts,
/// playbook, and inventory; then come the tags and the terminal. The toolbar holds only actions.
struct WorkspaceView: View {
    @Environment(AppState.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Bindable var workspace: Workspace
    /// Which columns show, kept across launches.
    @SceneStorage("columnVisibility") private var storedVisibility = "all"

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            InventoryPane(workspace: workspace)
        } content: {
            TagsPane(workspace: workspace)
        } detail: {
            // Attached to the detail column so the actions sit over the run, not the tags list.
            TerminalPane(workspace: workspace)
                .toolbar { toolbar }
        }
        // The window keeps its title for the Window menu; the sidebar shows the folder instead.
        .navigationTitle(workspace.name)
        .toolbar(removing: .title)
        // Undo can't reach a folder that's no longer open.
        .onDisappear { undoManager?.removeAllActions(withTarget: workspace) }
        // Drop another folder on the window to switch to it.
        .dropDestination(for: URL.self) { urls, _ in
            guard !app.terminal.isRunning, let url = urls.first(where: \.isFolder) else { return false }
            Task { await app.open(url) }
            return true
        }
        .confirmationDialog(
            "Run in live mode?",
            isPresented: Binding(
                get: { app.pendingLiveRun != nil },
                set: { if !$0 { app.pendingLiveRun = nil } }
            ),
            presenting: app.pendingLiveRun
        ) { command in
            Button("Run Live", role: .destructive) {
                app.pendingLiveRun = nil
                app.run(command, confirmed: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("Run in Check Mode") {
                app.pendingLiveRun = nil
                var check = command
                check.mode = .check
                app.run(check)
            }
            Button("Cancel", role: .cancel) { app.pendingLiveRun = nil }
        } message: { command in
            Text("This will make real changes.\n\n\(ShellQuoting.format(command.argv))")
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch storedVisibility {
                case "doubleColumn": .doubleColumn
                case "detailOnly": .detailOnly
                default: .all
                }
            },
            set: { visibility in
                switch visibility {
                case .doubleColumn: storedVisibility = "doubleColumn"
                case .detailOnly: storedVisibility = "detailOnly"
                default: storedVisibility = "all"
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Mode", selection: $workspace.mode) {
                Label("Check", systemImage: "checkmark.shield").tag(RunMode.check)
                Label("Live", systemImage: "bolt.fill").tag(RunMode.live)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help("Check mode (--check) reports what would change. Live mode makes changes.")
        }

        ToolbarItem(placement: .primaryAction) {
            if app.terminal.isRunning {
                Button("Stop", systemImage: "stop.fill") { app.stop() }
                    .help("Stop the run (⌘.)")
            } else {
                Button("Run", systemImage: "play.fill") { app.runCurrent() }
                    .tint(workspace.mode == .live ? .red : nil)
                    .disabled(!app.canRun)
                    .help(workspace.mode == .live ? "Run live (⌘R)" : "Run in check mode (⌘R)")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HistoryMenu(workspace: workspace)
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Reload", systemImage: "arrow.clockwise") {
                Task { await app.reload() }
            }
            .disabled(workspace.isDiscovering)
            .help("Reload inventories, playbooks, and tags (⇧⌘R)")
        }
    }
}

/// Past runs from the shared history file, each re-runnable in either mode.
struct HistoryMenu: View {
    @Environment(AppState.self) private var app
    let workspace: Workspace

    var body: some View {
        Menu {
            if workspace.history.isEmpty {
                Text("No Previous Runs")
            }
            ForEach(Array(workspace.history.prefix(15).enumerated()), id: \.offset) { _, argv in
                Menu(title(for: argv)) {
                    Button("Run in Check Mode", systemImage: "checkmark.shield") {
                        app.rerun(argv, mode: .check)
                    }
                    Button("Run Live…", systemImage: "bolt.fill") {
                        app.rerun(argv, mode: .live)
                    }
                    Divider()
                    Button("Restore Selections") {
                        if let command = AnsibleCommand(argv: argv) {
                            workspace.apply(command)
                        }
                    }
                    Button("Copy Command") { copyCommand(argv) }
                }
                .disabled(app.terminal.isRunning)
            }
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .help("Previous runs")
    }

    private func title(for argv: [String]) -> String {
        guard let command = AnsibleCommand(argv: argv) else { return ShellQuoting.format(argv) }
        var parts = [command.playbook]
        if !command.limit.isEmpty { parts.append("on " + command.limit.joined(separator: ",")) }
        if !command.tags.isEmpty { parts.append("tags " + command.tags.joined(separator: ",")) }
        parts.append(command.mode == .check ? "(check)" : "(live)")
        return parts.joined(separator: " ")
    }
}

/// Open Folder, recent folders, and Reveal in Finder, for the folder menu in the sidebar.
struct FolderMenuItems: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button("Open Folder…") { app.chooseDirectory() }
        if !app.recentDirectories.isEmpty {
            Divider()
            ForEach(app.recentDirectories, id: \.self) { url in
                Button(url.path.abbreviatingHome) {
                    Task { await app.open(url) }
                }
            }
        }
        if let workspace = app.workspace {
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([workspace.directory])
            }
        }
    }
}

/// Puts a command on the pasteboard as shell-quoted text, ready to paste into Terminal.
func copyCommand(_ argv: [String]) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(ShellQuoting.format(argv), forType: .string)
}

extension URL {
    var isFolder: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
