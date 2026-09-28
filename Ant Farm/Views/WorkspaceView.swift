//
//  WorkspaceView.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// The three-pane window for an open workspace. The sidebar holds the folder, hosts,
/// playbook, and inventory; then come the tags and the terminal, side by side under one
/// toolbar. The toolbar holds only actions, and View > Customize Toolbar can add or
/// rearrange them.
struct WorkspaceView: View {
    @Environment(AppState.self) private var app
    @Environment(WindowSession.self) private var session
    @Bindable var workspace: Workspace
    /// Which columns show, kept across launches.
    @SceneStorage("columnVisibility") private var storedVisibility = "all"

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            InventoryPane(workspace: workspace)
        } detail: {
            // Tags and the run share the detail column, so the toolbar spans both and the
            // divider between them stops below it instead of reaching into the title bar.
            HSplitView {
                TagsPane(workspace: workspace)
                TerminalPane(workspace: workspace)
                    .frame(minWidth: 420, maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .toolbar(id: "workspace.v2") { toolbar }
        }
        // The window keeps its title for the Window menu; the sidebar shows the folder instead.
        .navigationTitle(workspace.name)
        .toolbar(removing: .title)
        // Edit > Filter Hosts brings back the sidebar that holds the host filter.
        .onChange(of: session.focusRequest) { _, target in
            if target == .hosts && storedVisibility != "all" {
                storedVisibility = "all"
            }
        }
        // Drop another folder on the window to open it in its own window.
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(\.isFolder)
            folders.forEach { app.open($0) }
            return !folders.isEmpty
        }
        .confirmationDialog(
            "Run in live mode?",
            isPresented: Binding(
                get: { session.pendingLiveRun != nil },
                set: { if !$0 { session.pendingLiveRun = nil } }
            ),
            presenting: session.pendingLiveRun
        ) { command in
            Button("Run Live", role: .destructive) {
                session.pendingLiveRun = nil
                session.run(command, confirmed: true)
            }
            .keyboardShortcut(.defaultAction)
            Button("Run in Check Mode") {
                session.pendingLiveRun = nil
                var check = command
                check.mode = .check
                session.run(check)
            }
            Button("Cancel", role: .cancel) { session.pendingLiveRun = nil }
        } message: { command in
            Text("This will make real changes.\n\n\(ShellQuoting.format(command.argv))")
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            // Earlier versions had three columns and stored "doubleColumn" for a hidden sidebar.
            get: { storedVisibility == "all" ? .all : .detailOnly },
            set: { storedVisibility = $0 == .detailOnly ? "detailOnly" : "all" }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some CustomizableToolbarContent {
        // Sits at the leading edge, beside the sidebar button.
        ToolbarItem(id: "reload", placement: .navigation) {
            Button("Reload", systemImage: "arrow.clockwise") {
                Task { await session.reload() }
            }
            .disabled(workspace.isDiscovering)
            .help("Reload inventories, playbooks, and tags (⇧⌘R)")
        }

        // Pushes the rest to the trailing edge, with Run last.
        ToolbarSpacer(.flexible)

        ToolbarItem(id: "history", placement: .automatic) {
            HistoryMenu(workspace: workspace)
        }

        ToolbarItem(id: "mode", placement: .automatic) {
            Picker("Mode", selection: $workspace.mode) {
                Label("Check", systemImage: "checkmark.shield").tag(RunMode.check)
                Label("Live", systemImage: "bolt.fill").tag(RunMode.live)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help("Check mode (--check) reports what would change. Live mode makes changes.")
        }

        ToolbarItem(id: "run", placement: .automatic) {
            if session.terminal.isRunning {
                Button("Stop", systemImage: "stop.fill") { session.stop() }
                    .help("Stop the run (⌘.)")
            } else {
                Button("Run", systemImage: "play.fill") { session.runCurrent() }
                    .tint(workspace.mode == .live ? .red : nil)
                    .disabled(!session.canRun)
                    .help(workspace.mode == .live ? "Run live (⌘R)" : "Run in check mode (⌘R)")
            }
        }

        ToolbarItem(id: "copyCommand", placement: .automatic, showsByDefault: false) {
            Button("Copy Command", systemImage: "doc.on.doc") {
                if let argv = session.displayedCommand { copyCommand(argv) }
            }
            .disabled(session.displayedCommand == nil)
            .help("Copy the command (⇧⌘C)")
        }

        ToolbarItem(id: "finder", placement: .automatic, showsByDefault: false) {
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([workspace.directory])
            }
            .help("Show the folder in Finder")
        }

        ToolbarItem(id: "terminal", placement: .automatic, showsByDefault: false) {
            Button("Open in Terminal", systemImage: "apple.terminal") {
                openInTerminal(workspace.directory)
            }
            .help("Open the folder in Terminal")
        }
    }
}

/// Past runs from the shared history file, each re-runnable in either mode.
struct HistoryMenu: View {
    @Environment(WindowSession.self) private var session
    let workspace: Workspace

    var body: some View {
        Menu {
            if workspace.history.isEmpty {
                Text("No Previous Runs")
            }
            ForEach(Array(workspace.history.prefix(15).enumerated()), id: \.offset) { _, argv in
                Menu(title(for: argv)) {
                    Button("Run in Check Mode", systemImage: "checkmark.shield") {
                        session.rerun(argv, mode: .check)
                    }
                    Button("Run Live…", systemImage: "bolt.fill") {
                        session.rerun(argv, mode: .live)
                    }
                    Divider()
                    Button("Restore Selections") {
                        if let command = AnsibleCommand(argv: argv) {
                            workspace.apply(command)
                        }
                    }
                    Button("Copy Command") { copyCommand(argv) }
                }
                .disabled(session.terminal.isRunning)
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

/// Open Folder, recent folders, Show in Finder, and Open in Terminal, for the folder menu in the sidebar.
struct FolderMenuItems: View {
    @Environment(AppState.self) private var app
    @Environment(WindowSession.self) private var session

    var body: some View {
        Button("Open Folder…") { app.chooseDirectory(for: session) }
        let recents = app.recentDirectories.filter { $0 != session.directory }
        if !recents.isEmpty {
            Divider()
            ForEach(recents, id: \.self) { url in
                Button(url.path.abbreviatingHome) { app.open(url) }
            }
        }
        if let directory = session.directory {
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
            Button("Open in Terminal") { openInTerminal(directory) }
        }
    }
}

/// Opens a Terminal window at a folder, e.g. to run Ansible by hand.
func openInTerminal(_ directory: URL) {
    guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
    NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
}

/// Puts a command on the pasteboard as shell-quoted text, ready to paste into Terminal.
func copyCommand(_ argv: [String]) {
    copyLines([ShellQuoting.format(argv)])
}

extension URL {
    /// One spelling per folder, with or without a trailing slash or `..`, so windows can be matched to folders.
    var folderURL: URL {
        URL(fileURLWithPath: standardizedFileURL.path, isDirectory: true)
    }

    var isFolder: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
