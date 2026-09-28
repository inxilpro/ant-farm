//
//  Ant_FarmApp.swift
//  Ant Farm
//
//  Created by Chris Morrell on 9/25/26.
//

import AppKit
import SwiftUI
import UserNotifications

@main
struct Ant_FarmApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var app: AppState { delegate.app }

    var body: some Scene {
        // One window per folder. SwiftUI restores each window's folder on relaunch.
        WindowGroup("Ant Farm", id: "workspace", for: URL.self) { $directory in
            RootView(directory: $directory)
                .environment(app)
        }
        .defaultSize(width: 1300, height: 800)
        .commands {
            AppCommands(app: app)
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

/// Owns the app state, confirms quitting during a run, and answers run notifications.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let app: AppState

    override init() {
        AppDefaults.register()
        app = AppState()
        _ = UpdaterController.shared
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = app.sessions.filter(\.terminal.isRunning)
        if !running.isEmpty {
            let alert = NSAlert()
            alert.messageText = running.count == 1 ? "A run is in progress." : "\(running.count) runs are in progress."
            alert.informativeText = "Quitting stops Ansible, which may leave hosts partly changed."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: running.count == 1 ? "Stop Run and Quit" : "Stop Runs and Quit")
            alert.buttons[1].hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            running.forEach { $0.terminal.forceStop() }
        }
        app.isTerminating = true
        return .terminateNow
    }

    // Clicking a run's notification brings its window forward.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo[RunNotifier.directoryKey] as? String else { return }
        await MainActor.run {
            app.open(URL(fileURLWithPath: path))
        }
    }
}

/// The menu bar. Window-specific items act on the key window's session.
private struct AppCommands: Commands {
    let app: AppState
    @FocusedValue(WindowSession.self) private var session
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.runView) private var runView = RunView.summary
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 12.0

    private var workspace: Workspace? { session?.workspace }
    private var isRunning: Bool { session?.terminal.isRunning ?? false }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                .disabled(!UpdaterController.shared.canCheckForUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "workspace") }
                .keyboardShortcut("n")
            Button("Open Folder…") { app.chooseDirectory(for: session) }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recentDirectories, id: \.self) { url in
                    Button(url.path.abbreviatingHome) { app.open(url, preferring: session) }
                }
                Divider()
                Button("Clear Menu") { app.clearRecents() }
                    .disabled(app.recentDirectories.isEmpty)
            }
            Divider()
            Button("Show in Finder") {
                if let directory = workspace?.directory {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            }
            .disabled(workspace == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Command") {
                if let argv = session?.displayedCommand { copyCommand(argv) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(session?.displayedCommand == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Filter Hosts") { session?.focusRequest = .hosts }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(workspace == nil)
            Button("Filter Tags") { session?.focusRequest = .tags }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
                .disabled(workspace == nil)
        }

        SidebarCommands()
        ToolbarCommands()

        CommandGroup(before: .toolbar) {
            Toggle("Show Terminal", isOn: Binding(
                get: { (session?.isTerminalForced ?? false) || runView == .terminal },
                set: { runView = $0 ? .terminal : .summary }
            ))
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(session == nil || session?.terminal.status == .idle || session?.isTerminalForced == true)
            Divider()
            Button("Bigger") { setFontSize(fontSize + 1) }
                .keyboardShortcut("+")
                .disabled(fontSize >= 32)
            Button("Smaller") { setFontSize(fontSize - 1) }
                .keyboardShortcut("-")
                .disabled(fontSize <= 8)
            Button("Default Font Size") { setFontSize(12) }
                .keyboardShortcut("0")
                .disabled(fontSize == 12)
            Divider()
        }

        CommandMenu("Run") {
            Button("Run") { session?.runCurrent() }
                .keyboardShortcut("r")
                .disabled(!(session?.canRun ?? false))
            Button("Run in Check Mode") { session?.runCurrent(mode: .check) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!(session?.canRun ?? false))
            Button("Stop") { session?.stop() }
                .keyboardShortcut(".")
                .disabled(!isRunning)
            Button("Force Stop") { session?.terminal.forceStop() }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(!isRunning)
            Divider()
            // Toggles, so the menu shows a checkmark next to the current mode.
            Toggle("Check Mode", isOn: modeBinding(.check))
                .keyboardShortcut("1")
                .disabled(workspace == nil)
            Toggle("Live Mode", isOn: modeBinding(.live))
                .keyboardShortcut("2")
                .disabled(workspace == nil)
            Divider()
            Button("Clear Run") { session?.clearRun() }
                .keyboardShortcut("k")
                .disabled(session == nil || isRunning)
            Button("Reload") { Task { await session?.reload() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Ant Farm Help") { openWeb("https://github.com/inxilpro/ant-farm#readme") }
            Button("Release Notes") { openWeb("https://github.com/inxilpro/ant-farm/releases") }
            Divider()
            Button("Report an Issue…") { openWeb("https://github.com/inxilpro/ant-farm/issues/new") }
        }
    }

    private func modeBinding(_ mode: RunMode) -> Binding<Bool> {
        Binding(
            get: { workspace?.mode == mode },
            set: { if $0 { workspace?.mode = mode } }
        )
    }

    private func setFontSize(_ size: Double) {
        fontSize = min(max(size, 8), 32)
        app.setTerminalFontSize(fontSize)
    }

    private func openWeb(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
