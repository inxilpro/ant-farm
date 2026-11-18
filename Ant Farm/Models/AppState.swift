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
    /// `antfarm://` links that arrived before `start()` finished.
    @ObservationIgnored private var pendingLinkURLs: [URL] = []
    /// Links waiting for their folder's window to finish loading, by folder.
    @ObservationIgnored private var pendingLinks: [URL: DeepLink] = [:]
    /// Set while an open panel is up, so a launch doesn't show a second one.
    @ObservationIgnored private(set) var isChoosingFolder = false
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
                let links = pendingLinkURLs
                pendingLinkURLs = []
                links.forEach(openLink)
            }
        }
        await startTask?.value
    }

    /// The folder to reopen in the first empty window of a launch, when the system restored none.
    func folderToRestore() -> URL? {
        guard !restoredLastFolder, pendingOpen == nil, pendingLinkURLs.isEmpty, !sessions.contains(where: { $0.directory != nil }) else { return nil }
        restoredLastFolder = true
        guard let path = AppDefaults.store.string(forKey: SettingsKey.lastDirectory),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Opens a folder dropped on the Dock icon, chosen with Open With, or picked from the Dock's
    /// recent items, or an `antfarm://` link.
    func openFromSystem(_ url: URL) {
        let isLink = DeepLink.handles(url)
        guard started else {
            if isLink {
                pendingLinkURLs.append(url)
            } else {
                pendingOpen = url
            }
            return
        }
        if isLink {
            openLink(url)
        } else {
            open(url)
        }
    }

    // MARK: Links

    /// Opens the folder an `antfarm://` link names and makes its selections there.
    func openLink(_ url: URL) {
        let link: DeepLink
        do {
            link = try DeepLink(url: url)
        } catch {
            showAlert("Ant Farm can’t open this link.", error.localizedDescription)
            return
        }
        // Folders in open windows come first, so a link goes to the clone already on screen.
        let candidates = sessions.compactMap(\.directory) + recentDirectories
        if let folder = link.folders(among: candidates).first {
            open(folder, applying: link)
            return
        }
        switch link.location {
        case let .repository(repo, folder):
            chooseDirectory(message: "Choose your copy of \(repo) to open the link.") { [weak self] chosen in
                guard let self else { return }
                if let folder = link.folders(among: [chosen]).first {
                    open(folder, applying: link)
                } else {
                    let inside = folder.map { " with a “\($0)” folder" } ?? ""
                    showAlert("“\(chosen.lastPathComponent)” isn’t a copy of \(repo)\(inside).",
                              "Choose a folder in a git repository whose remote is \(repo).")
                }
            }
        case let .path(path):
            showAlert("The folder “\(path)” can’t be found.", "The link opens a folder at that path on this Mac.")
        }
    }

    /// Opens a folder and makes a link's selections once its window has loaded it.
    func open(_ folder: URL, applying link: DeepLink) {
        let folder = folder.folderURL
        pendingLinks[folder] = link
        open(folder)
        sessions.first { $0.directory == folder }?.applyPendingLink()
    }

    /// The link waiting for a folder, if there is one. Each link is handed out once.
    func takeLink(for folder: URL) -> DeepLink? {
        pendingLinks.removeValue(forKey: folder.folderURL)
    }

    private func showAlert(_ message: String, _ information: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
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
        chooseDirectory(for: session, message: "Choose a folder that contains your Ansible inventory and playbooks.") { [weak self] url in
            self?.open(url, preferring: session)
        }
    }

    private func chooseDirectory(for session: WindowSession? = nil, message: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = message
        if let current = session?.directory ?? recentDirectories.first {
            panel.directoryURL = current
        }
        isChoosingFolder = true
        let handler = { [weak self] (response: NSApplication.ModalResponse) in
            self?.isChoosingFolder = false
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
        if let window = session?.window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
