//
//  WindowSession.swift
//  Ant Farm
//

import AppKit
import Foundation
import Observation

/// One window's state: its folder, its terminal, and the run in progress there.
@Observable
final class WindowSession {
    private(set) var workspace: Workspace?

    let terminal = TerminalController()
    /// The native report of the current run, fed by the bundled callback plugin.
    let monitor = RunMonitor()

    /// A live run waiting for the user to confirm it.
    var pendingLiveRun: AnsibleCommand?
    /// Set by Edit > Filter Hosts / Filter Tags; the pane with that filter takes focus and clears it.
    var focusRequest: FilterTarget?

    @ObservationIgnored weak var app: AppState?
    /// The window showing this session, for bringing it to the front and attaching sheets.
    @ObservationIgnored weak var window: NSWindow? {
        didSet {
            guard window !== oldValue else { return }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            // Not onDisappear: SwiftUI sends that when a window becomes a background tab too.
            closeObserver = window.map {
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: $0, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.windowWillClose()
                    }
                }
            }
        }
    }
    @ObservationIgnored private var closeObserver: Any?
    @ObservationIgnored private var loading: URL?
    /// Changes the folder the window presents, which SwiftUI restores on relaunch. Set by `RootView`.
    @ObservationIgnored var presentFolder: ((URL?) -> Void)?

    /// The folder this window shows, or is about to once it has loaded.
    @ObservationIgnored private(set) var directory: URL?

    init() {
        _ = NotificationCenter.default.addObserver(forName: .antFarmRunFinished, object: terminal, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runFinished()
            }
        }
    }

    /// Shows a folder in this window.
    func show(_ directory: URL) {
        let directory = directory.folderURL
        self.directory = directory
        presentFolder?(directory)
        bringToFront()
    }

    /// Loads the folder the window presents. Called when that folder changes.
    func load(_ directory: URL?) async {
        guard let directory = directory?.folderURL else {
            self.directory = nil
            workspace = nil
            return
        }
        // A restored window's folder may have been deleted, or be on a drive that isn't mounted.
        guard directory.isFolder else {
            presentFolder?(nil)
            app?.removeRecent(directory)
            showMissingFolder(directory)
            return
        }
        self.directory = directory
        // SwiftUI can start this task twice for one window; discovery should only run once.
        guard directory != workspace?.directory, directory != loading else { return }
        loading = directory
        defer { loading = nil }
        await app?.start()
        guard directory == self.directory else { return }
        let workspace = Workspace(directory: directory, tools: app?.tools)
        self.workspace = workspace
        app?.noteOpened(directory)
        await workspace.reload()
    }

    private func showMissingFolder(_ directory: URL) {
        let alert = NSAlert()
        alert.messageText = "“\(directory.lastPathComponent)” can’t be found."
        alert.informativeText = "It may have been moved, renamed, or be on a drive that isn’t connected: \(directory.path.abbreviatingHome)"
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func bringToFront() {
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() async {
        await app?.locateTools()
        await workspace?.reload()
    }

    /// Stops any run and forgets its report.
    private func windowWillClose() {
        terminal.forceStop()
        monitor.clear()
        app?.unregister(self)
    }

    // MARK: Running

    var canRun: Bool {
        app?.tools != nil && workspace?.selectedPlaybook != nil && !terminal.isRunning
    }

    /// Runs the current selections, asking first when it's a live run.
    func runCurrent(mode: RunMode? = nil) {
        let diff = UserDefaults.standard.bool(forKey: SettingsKey.alwaysDiff)
        guard let command = workspace?.command(mode: mode, diff: diff) else { return }
        run(command)
    }

    func run(_ command: AnsibleCommand, confirmed: Bool = false) {
        guard !terminal.isRunning else { return }
        if command.mode == .live && !confirmed && UserDefaults.standard.bool(forKey: SettingsKey.confirmLiveRuns) {
            pendingLiveRun = command
            return
        }
        guard let workspace, let tools = app?.tools else { return }

        let argv = command.argv
        if UserDefaults.standard.bool(forKey: SettingsKey.saveHistory) {
            workspace.recordRun(argv)
        }
        var environment = tools.terminalEnvironment
        environment.merge(monitor.start(argv: argv, callbackPluginPaths: workspace.callbackPluginPaths)) { $1 }
        terminal.run(
            argv: argv,
            executable: tools.playbook,
            environment: environment,
            directory: workspace.directory,
            mode: command.mode
        )
    }

    func rerun(_ argv: [String], mode: RunMode) {
        guard var command = AnsibleCommand(argv: argv) else { return }
        command.mode = mode
        workspace?.apply(command)
        run(command)
    }

    func stop() {
        terminal.stop()
    }

    /// The command the run pane shows: the run in progress (or just finished), else the next one.
    var displayedCommand: [String]? {
        if terminal.status != .idle, let command = terminal.command {
            return command
        }
        let diff = UserDefaults.standard.bool(forKey: SettingsKey.alwaysDiff)
        return workspace?.command(diff: diff)?.argv
    }

    /// The terminal takes over when Ansible needs input, or when there's no report to show.
    var isTerminalForced: Bool {
        guard terminal.status != .idle else { return false }
        if monitor.report.isWaitingForInput { return true }
        return !monitor.report.hasEvents && (!terminal.isRunning || !monitor.isAvailable)
    }

    /// Clears the terminal and the report of the last run.
    func clearRun() {
        guard !terminal.isRunning else { return }
        terminal.clear()
        monitor.clear()
    }

    private func runFinished() {
        monitor.finish()
        guard !NSApp.isActive, let workspace else { return }
        NSApp.requestUserAttention(.informationalRequest)
        RunNotifier.post(status: terminal.status, mode: terminal.mode ?? workspace.mode, workspace: workspace.name, directory: workspace.directory, recap: monitor.report.recap)
    }
}

/// A filter field that Edit > Filter Hosts or Filter Tags can focus.
enum FilterTarget {
    case hosts
    case tags
}
