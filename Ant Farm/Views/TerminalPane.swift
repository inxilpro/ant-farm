//
//  TerminalPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// Third pane: the command about to run (or running), then what the run will do,
/// is doing, or did. Ansible's own output is one click away in the terminal.
struct TerminalPane: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.runView) private var runView = RunView.summary
    let workspace: Workspace

    private var report: RunReport { app.monitor.report }

    private var isTerminalForced: Bool { app.isTerminalForced }

    private var showsTerminal: Bool {
        guard app.terminal.status != .idle else { return false }
        return isTerminalForced || runView == .terminal
    }

    var body: some View {
        VStack(spacing: 0) {
            CommandHeader(workspace: workspace, runView: $runView, showsTerminal: showsTerminal, isTerminalForced: isTerminalForced)
            Divider()
            if report.isWaitingForInput && app.terminal.isRunning {
                Label("Ansible is waiting for input. Type your answer in the terminal.", systemImage: "keyboard")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.2))
                Divider()
            }
            ZStack {
                TerminalHost(controller: app.terminal, isVisible: showsTerminal)
                    .padding(.leading, 6)
                    .background(Color(nsColor: .textBackgroundColor))
                if !showsTerminal {
                    Group {
                        if app.terminal.status == .idle {
                            PlanView(workspace: workspace)
                        } else {
                            RunReportView(report: report, isRunning: app.terminal.isRunning) {
                                runView = .terminal
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .onChange(of: showsTerminal) { _, shows in
            if shows && app.terminal.isRunning {
                app.terminal.focus()
            }
        }
    }
}

private struct CommandHeader: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.alwaysDiff) private var alwaysDiff = true
    let workspace: Workspace
    @Binding var runView: RunView
    let showsTerminal: Bool
    let isTerminalForced: Bool

    private var terminal: TerminalController { app.terminal }

    /// While a run is in progress (or just finished), show its command; otherwise preview the next one.
    private var argv: [String]? {
        if terminal.status != .idle, let command = terminal.command {
            return command
        }
        return workspace.command(diff: alwaysDiff)?.argv
    }

    private var mode: RunMode {
        terminal.status != .idle ? (terminal.mode ?? workspace.mode) : workspace.mode
    }

    var body: some View {
        HStack(spacing: 10) {
            StatusBadge(status: terminal.status, mode: mode, startedAt: terminal.startedAt, finishedAt: terminal.finishedAt)

            if let argv {
                Text(ShellQuoting.format(argv))
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(ShellQuoting.format(argv))

                Button("Copy Command", systemImage: "doc.on.doc") {
                    copyCommand(argv)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy command (⇧⌘C)")
            } else {
                Text("Choose a playbook to run")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if terminal.status != .idle {
                Picker("View", selection: Binding(
                    get: { showsTerminal ? RunView.terminal : RunView.summary },
                    set: { runView = $0 }
                )) {
                    Label("Summary", systemImage: "list.bullet.rectangle").tag(RunView.summary)
                    Label("Terminal", systemImage: "terminal").tag(RunView.terminal)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .fixedSize()
                .disabled(isTerminalForced)
                .help(isTerminalForced ? "Showing the terminal: Ansible needs input or there's no summary for this run" : "Show Ant Farm's summary or Ansible's own output")
            }

            if terminal.status != .idle && !terminal.isRunning {
                Button("Clear", systemImage: "clear") { app.clearRun() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Clear the run and show what the next one will do (⌘K)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct StatusBadge: View {
    let status: TerminalController.Status
    let mode: RunMode
    let startedAt: Date?
    let finishedAt: Date?

    var body: some View {
        HStack(spacing: 5) {
            switch status {
            case .running:
                ProgressView().controlSize(.mini)
            case .finished(let code) where code == 0:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .finished:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            case .stopped:
                Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
            case .idle:
                EmptyView()
            }
            Text(mode == .live ? "LIVE" : "CHECK")
                .font(.caption.weight(.bold))
                .foregroundStyle(mode == .live ? Color.red : Color.accentColor)
            if let duration {
                Text(duration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((mode == .live ? Color.red : Color.accentColor).opacity(0.12), in: .capsule)
        .fixedSize()
    }

    private var duration: String? {
        guard let startedAt, let finishedAt else { return nil }
        return Duration.seconds(finishedAt.timeIntervalSince(startedAt))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
    }
}

/// Hosts the controller's long-lived terminal view inside SwiftUI.
///
/// The view stays attached while the summary covers it (so its size and scrollback
/// don't change); it's only hidden, so it doesn't take clicks or keystrokes.
private struct TerminalHost: NSViewRepresentable {
    let controller: TerminalController
    var isVisible = true

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        controller.view.isHidden = !isVisible
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if controller.view.superview !== container {
            attach(to: container)
        }
        controller.view.isHidden = !isVisible
    }

    private func attach(to container: NSView) {
        let view = controller.view
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
