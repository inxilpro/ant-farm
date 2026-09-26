//
//  Ant_FarmApp.swift
//  Ant Farm
//
//  Created by Chris Morrell on 9/25/26.
//

import AppKit
import SwiftUI

@main
struct Ant_FarmApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    private var app: AppState { delegate.app }

    var body: some Scene {
        Window("Ant Farm", id: "main") {
            RootView()
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

/// Owns the app state so folders opened from Finder or the Dock reach it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app: AppState

    override init() {
        AppDefaults.register()
        app = AppState()
        _ = UpdaterController.shared
        super.init()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: \.hasDirectoryPath) ?? urls.first else { return }
        app.openFromSystem(url)
    }
}

private struct AppCommands: Commands {
    let app: AppState
    @AppStorage(SettingsKey.runView) private var runView = RunView.summary
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 12.0

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                .disabled(!UpdaterController.shared.canCheckForUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { app.chooseDirectory() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recentDirectories, id: \.self) { url in
                    Button(url.path.abbreviatingHome) { Task { await app.open(url) } }
                }
                Divider()
                Button("Clear Menu") { app.clearRecents() }
                    .disabled(app.recentDirectories.isEmpty)
            }
            Divider()
            Button("Show in Finder") {
                if let directory = app.workspace?.directory {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            }
            .disabled(app.workspace == nil)
            Button("Close Folder") { app.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.workspace == nil || app.terminal.isRunning)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Command") {
                if let argv = app.displayedCommand { copyCommand(argv) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(app.displayedCommand == nil)
        }

        SidebarCommands()

        CommandGroup(before: .toolbar) {
            Toggle("Show Terminal", isOn: Binding(
                get: { app.isTerminalForced || runView == .terminal },
                set: { runView = $0 ? .terminal : .summary }
            ))
            .keyboardShortcut("t", modifiers: [.command, .control])
            .disabled(app.terminal.status == .idle || app.isTerminalForced)
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
            Button("Run") { app.runCurrent() }
                .keyboardShortcut("r")
                .disabled(!app.canRun)
            Button("Run in Check Mode") { app.runCurrent(mode: .check) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!app.canRun)
            Button("Stop") { app.stop() }
                .keyboardShortcut(".")
                .disabled(!app.terminal.isRunning)
            Button("Force Stop") { app.terminal.forceStop() }
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(!app.terminal.isRunning)
            Divider()
            // Toggles, so the menu shows a checkmark next to the current mode.
            Toggle("Check Mode", isOn: modeBinding(.check))
                .keyboardShortcut("1")
                .disabled(app.workspace == nil)
            Toggle("Live Mode", isOn: modeBinding(.live))
                .keyboardShortcut("2")
                .disabled(app.workspace == nil)
            Divider()
            Button("Clear Run") { app.clearRun() }
                .keyboardShortcut("k")
                .disabled(app.terminal.isRunning)
            Button("Reload") { Task { await app.reload() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(app.workspace == nil)
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
            get: { app.workspace?.mode == mode },
            set: { if $0 { app.workspace?.mode = mode } }
        )
    }

    private func setFontSize(_ size: Double) {
        fontSize = min(max(size, 8), 32)
        app.terminal.setFontSize(fontSize)
    }

    private func openWeb(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
