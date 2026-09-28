//
//  AppState.swift
//  Ant Farm
//

import AppKit
import Foundation
import Observation

/// App-wide state: the located Ansible tools, recent folders, and the open windows.
@Observable
final class AppState {
    private(set) var tools: AnsibleTools?
    private(set) var isLocatingTools = true
    private(set) var recentDirectories: [URL] = []
    /// Every open window, whether or not it shows a folder yet.
    private(set) var sessions: [WindowSession] = []

    @ObservationIgnored private var environment: [String: String]?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var restoredLastFolder = false
    /// A folder Finder or the Dock asked to open before `start()` finished.
    @ObservationIgnored private var pendingOpen: URL?
    /// Opens a new window for a folder. Set by `RootView`.
    @ObservationIgnored var openWindow: ((URL) -> Void)?
    /// Set once the app is quitting, when windows go away without the user closing them.
    @ObservationIgnored var isTerminating = false

    var isRunning: Bool { sessions.contains { $0.terminal.isRunning } }

    init() {
        recentDirectories = AppDefaults.recentDirectories.map { URL(fileURLWithPath: $0) }
    }

    func register(_ session: WindowSession) {
        session.app = self
        if !sessions.contains(where: { $0 === session }) {
            sessions.append(session)
        }
    }

    func unregister(_ session: WindowSession) {
        sessions.removeAll { $0 === session }
        // Closing a folder's window means not reopening it next launch. Quitting keeps it.
        guard !isTerminating, let directory = session.directory,
              AppDefaults.store.string(forKey: SettingsKey.lastDirectory) == directory.path else { return }
        if let other = sessions.lazy.compactMap(\.directory).first {
            AppDefaults.store.set(other.path, forKey: SettingsKey.lastDirectory)
        } else {
            AppDefaults.store.removeObject(forKey: SettingsKey.lastDirectory)
        }
    }

    /// Finds Ansible once per launch. Every window waits on this before loading its folder.
    func start() async {
        if startTask == nil {
            startTask = Task {
                await locateTools()
                started = true
                if let url = pendingOpen {
                    pendingOpen = nil
                    restoredLastFolder = true
                    open(url)
                }
            }
        }
        await startTask?.value
    }

    /// The folder to reopen in the first empty window of a launch, when the system restored none.
    func folderToRestore() -> URL? {
        guard !restoredLastFolder, pendingOpen == nil, !sessions.contains(where: { $0.directory != nil }) else { return nil }
        restoredLastFolder = true
        guard let path = AppDefaults.store.string(forKey: SettingsKey.lastDirectory),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Opens a folder dropped on the Dock icon, chosen with Open With, or picked from the Dock's recent items.
    func openFromSystem(_ url: URL) {
        guard started else {
            pendingOpen = url
            return
        }
        open(url)
    }

    /// Shows a folder: in the window that already has it, else in an empty window, else in a new one.
    func open(_ url: URL, preferring requester: WindowSession? = nil) {
        let url = url.folderURL
        if let existing = sessions.first(where: { $0.directory == url }) {
            existing.bringToFront()
        } else if let empty = requester.flatMap({ $0.directory == nil ? $0 : nil })
                    ?? sessions.first(where: { $0.directory == nil }) {
            empty.show(url)
        } else {
            openWindow?(url)
        }
    }

    /// Records a folder a window opened, for Open Recent and the next launch.
    func noteOpened(_ directory: URL) {
        AppDefaults.store.set(directory.path, forKey: SettingsKey.lastDirectory)
        var recents = AppDefaults.recentDirectories.filter { $0 != directory.path }
        recents.insert(directory.path, at: 0)
        AppDefaults.recentDirectories = recents
        recentDirectories = AppDefaults.recentDirectories.map { URL(fileURLWithPath: $0) }
        // The system's recent items outlive the UI tests' own defaults.
        if !AppDefaults.isUITesting {
            NSDocumentController.shared.noteNewRecentDocumentURL(directory)
        }
    }

    func locateTools() async {
        isLocatingTools = true
        defer { isLocatingTools = false }
        if environment == nil {
            // UI tests point Ant Farm at a fake Ansible, so the login shell (slow, and different on every Mac) isn't needed.
            environment = AppDefaults.isUITesting ? ProcessInfo.processInfo.environment : await LoginShell.environment()
        }
        let override = AppDefaults.store.string(forKey: SettingsKey.ansibleDirectory)
        tools = AnsibleTools.locate(environment: environment ?? [:], overrideDirectory: override)
        for session in sessions {
            session.workspace?.tools = tools
        }
    }

    func removeRecent(_ url: URL) {
        AppDefaults.recentDirectories = AppDefaults.recentDirectories.filter { $0 != url.path }
        recentDirectories = AppDefaults.recentDirectories.map { URL(fileURLWithPath: $0) }
    }

    func clearRecents() {
        AppDefaults.recentDirectories = []
        if !AppDefaults.isUITesting {
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
        recentDirectories = []
    }

    func setTerminalFontSize(_ size: Double) {
        for session in sessions {
            session.terminal.setFontSize(size)
        }
    }

    /// Shows an open panel for a folder, as a sheet on the requesting window when there is one.
    func chooseDirectory(for session: WindowSession? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder that contains your Ansible inventory and playbooks."
        if let current = session?.directory ?? recentDirectories.first {
            panel.directoryURL = current
        }
        let handler = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url, preferring: session)
        }
        if let window = session?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
