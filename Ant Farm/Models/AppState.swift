//
//  AppState.swift
//  Ant Farm
//

import AppKit
import Foundation
import Observation

/// App-wide state: the open workspace, the located Ansible tools, and the run in progress.
@Observable
final class AppState {
    private(set) var workspace: Workspace?
    private(set) var tools: AnsibleTools?
    private(set) var isLocatingTools = true
    private(set) var recentDirectories: [URL] = []

    let terminal = TerminalController()
    /// The native report of the current run, fed by the bundled callback plugin.
    let monitor = RunMonitor()

    /// A live run waiting for the user to confirm it.
    var pendingLiveRun: AnsibleCommand?

    @ObservationIgnored private var environment: [String: String]?

    init() {
        recentDirectories = AppDefaults.recentDirectories.map { URL(fileURLWithPath: $0) }
        _ = NotificationCenter.default.addObserver(forName: .antFarmRunFinished, object: terminal, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.monitor.finish()
            }
        }
    }

    /// Finds Ansible and reopens the last workspace. Returns false when there's no workspace to open.
    @discardableResult
    func start() async -> Bool {
        await locateTools()
        if let path = UserDefaults.standard.string(forKey: SettingsKey.lastDirectory),
           FileManager.default.fileExists(atPath: path) {
            await open(URL(fileURLWithPath: path))
            return true
        }
        return false
    }

    func locateTools() async {
        isLocatingTools = true
        defer { isLocatingTools = false }
        if environment == nil {
            environment = await LoginShell.environment()
        }
        let override = UserDefaults.standard.string(forKey: SettingsKey.ansibleDirectory)
        tools = AnsibleTools.locate(environment: environment ?? [:], overrideDirectory: override)
        workspace?.tools = tools
    }

    func open(_ directory: URL) async {
        let directory = directory.standardizedFileURL
        UserDefaults.standard.set(directory.path, forKey: SettingsKey.lastDirectory)
        var recents = AppDefaults.recentDirectories.filter { $0 != directory.path }
        recents.insert(directory.path, at: 0)
        AppDefaults.recentDirectories = recents
        recentDirectories = AppDefaults.recentDirectories.map { URL(fileURLWithPath: $0) }

        let workspace = Workspace(directory: directory, tools: tools)
        self.workspace = workspace
        NSDocumentController.shared.noteNewRecentDocumentURL(directory)
        await workspace.reload()
    }

    func reload() async {
        await locateTools()
        await workspace?.reload()
    }

    func closeWorkspace() {
        workspace = nil
        UserDefaults.standard.removeObject(forKey: SettingsKey.lastDirectory)
    }

    func clearRecents() {
        AppDefaults.recentDirectories = []
        recentDirectories = []
    }

    /// Shows an open panel for choosing a workspace folder.
    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder that contains your Ansible inventory and playbooks."
        if let current = workspace?.directory ?? recentDirectories.first {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await open(url) }
    }

    // MARK: Running

    var canRun: Bool {
        tools != nil && workspace?.selectedPlaybook != nil && !terminal.isRunning
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
        guard let workspace, let tools else { return }

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

    /// Clears the terminal and the report of the last run.
    func clearRun() {
        guard !terminal.isRunning else { return }
        terminal.clear()
        monitor.clear()
    }
}
