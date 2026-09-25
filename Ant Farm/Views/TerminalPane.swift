//
//  TerminalPane.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// Third pane: the command about to run (or running) and the terminal showing its output.
struct TerminalPane: View {
    @Environment(AppState.self) private var app
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            CommandHeader(workspace: workspace)
            Divider()
            TerminalHost(controller: app.terminal)
                .padding(.leading, 6)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct CommandHeader: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKey.alwaysDiff) private var alwaysDiff = true
    let workspace: Workspace

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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ShellQuoting.format(argv), forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy command")
            } else {
                Text("Choose a playbook to run")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if terminal.status != .idle && !terminal.isRunning {
                Button("Clear", systemImage: "clear") { terminal.clear() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Clear the terminal (⌘K)")
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
private struct TerminalHost: NSViewRepresentable {
    let controller: TerminalController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if controller.view.superview !== container {
            attach(to: container)
        }
    }

    private func attach(to container: NSView) {
        let view = controller.view
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }
}
