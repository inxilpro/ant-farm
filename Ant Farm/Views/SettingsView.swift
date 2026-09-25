//
//  SettingsView.swift
//  Ant Farm
//

import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Terminal", systemImage: "terminal") { TerminalSettings() }
            Tab("Updates", systemImage: "arrow.triangle.2.circlepath") { UpdateSettings() }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.ansibleDirectory) private var ansibleDirectory = ""
    @AppStorage(SettingsKey.confirmLiveRuns) private var confirmLiveRuns = true
    @AppStorage(SettingsKey.alwaysDiff) private var alwaysDiff = true
    @AppStorage(SettingsKey.saveHistory) private var saveHistory = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Ansible folder") {
                    HStack {
                        TextField("Ansible folder", text: $ansibleDirectory, prompt: Text("Found automatically"))
                            .labelsHidden()
                            .onSubmit { relocate() }
                        Button("Choose…") { chooseFolder() }
                    }
                }
                LabeledContent("Using") {
                    if app.isLocatingTools {
                        ProgressView().controlSize(.small)
                    } else if let tools = app.tools {
                        Text(tools.playbook.path)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("ansible-playbook not found").foregroundStyle(.red)
                    }
                }
            } footer: {
                Text("Leave empty to search your login shell's PATH, Homebrew, and ~/.local/bin.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Confirm before live runs", isOn: $confirmLiveRuns)
                Toggle("Show diffs (--diff)", isOn: $alwaysDiff)
                Toggle("Save runs to .ansible-interactive-history", isOn: $saveHistory)
            }
        }
        .formStyle(.grouped)
        .onChange(of: ansibleDirectory) { _, newValue in
            if newValue.isEmpty { relocate() }
        }
    }

    private func relocate() {
        Task { await app.locateTools() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the folder that contains ansible-playbook."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ansibleDirectory = url.path
        relocate()
    }
}

private struct TerminalSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 12.0

    var body: some View {
        Form {
            Stepper(value: $fontSize, in: 8...32, step: 1) {
                LabeledContent("Font size", value: "\(Int(fontSize)) pt")
            }
        }
        .formStyle(.grouped)
        .onChange(of: fontSize) { _, size in
            app.terminal.setFontSize(size)
        }
    }
}

private struct UpdateSettings: View {
    @Bindable private var updater = UpdaterController.shared

    var body: some View {
        Form {
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!UpdaterController.isEnabled)
            LabeledContent("Version", value: Bundle.main.versionDescription)
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return version == build ? version : "\(version) (\(build))"
    }
}
