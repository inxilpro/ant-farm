//
//  Ant_FarmApp.swift
//  Ant Farm
//
//  Created by Chris Morrell on 9/25/26.
//

import SwiftUI

@main
struct Ant_FarmApp: App {
    @State private var app: AppState

    init() {
        AppDefaults.register()
        _app = State(initialValue: AppState())
        _ = UpdaterController.shared
    }

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

private struct AppCommands: Commands {
    let app: AppState

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
            Button("Close Folder") { app.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.workspace == nil || app.terminal.isRunning)
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
            Button("Check Mode") { app.workspace?.mode = .check }
                .keyboardShortcut("1")
                .disabled(app.workspace == nil)
            Button("Live Mode") { app.workspace?.mode = .live }
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
    }
}
