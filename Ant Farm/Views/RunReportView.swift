//
//  RunReportView.swift
//  Ant Farm
//

import SwiftUI

/// During and after a run: plays, tasks, and each host's result, from the callback plugin's events.
struct RunReportView: View {
    let report: RunReport
    let isRunning: Bool
    let showTerminal: () -> Void

    @AppStorage(SettingsKey.onlyChanges) private var onlyChanges = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<String> = []
    @State private var collapsed: Set<String> = []

    var body: some View {
        if !report.hasEvents {
            ContentUnavailableView {
                Label("Starting…", systemImage: "hourglass")
            } description: {
                Text("Waiting for Ansible to start the playbook.")
            } actions: {
                Button("Show Terminal", action: showTerminal)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RecapView(recap: report.recap, isFinal: report.stats != nil)
                        ForEach(report.plays) { play in
                            playSection(play)
                        }
                        if report.noHostsRemaining {
                            Label("No hosts remaining: every host failed or was unreachable.", systemImage: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 1000, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: report.currentTask?.id) { _, id in
                    guard isRunning, let id else { return }
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Toggle("Only changes and failures", isOn: $onlyChanges)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button("Expand All") {
                        expanded = Set(report.tasks.map(\.id))
                        collapsed = []
                    }
                    Button("Collapse All") {
                        collapsed = Set(report.tasks.map(\.id))
                        expanded = []
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }

    private func playSection(_ play: RunReport.PlayReport) -> some View {
        let tasks = onlyChanges ? play.tasks.filter { !$0.isQuiet } : play.tasks
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(play.name.isEmpty ? "Play" : play.name)
                    .font(.headline)
                Spacer()
                Text("hosts: \(play.pattern)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if play.noHostsMatched {
                Divider()
                Label("No hosts matched, so this play was skipped.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(14)
            } else if tasks.isEmpty {
                Divider()
                Text(play.tasks.isEmpty ? "No tasks yet." : "No changes or failures.")
                    .foregroundStyle(.secondary)
                    .padding(14)
            }

            ForEach(tasks) { task in
                Divider()
                TaskRow(task: task, isExpanded: expansion(for: task))
                    .id(task.id)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    /// Failed tasks open by themselves; everything else waits for a click.
    private func expansion(for task: RunReport.TaskReport) -> Binding<Bool> {
        Binding {
            expanded.contains(task.id) || (task.needsAttention && !collapsed.contains(task.id))
        } set: { open in
            if open {
                expanded.insert(task.id)
                collapsed.remove(task.id)
            } else {
                expanded.remove(task.id)
                collapsed.insert(task.id)
            }
        }
    }
}

// MARK: Recap

private struct RecapView: View {
    let recap: [RunReport.HostRecap]
    let isFinal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(isFinal ? "Recap" : "Progress")
                    .font(.headline)
                Spacer()
                Text(headline)
                    .foregroundStyle(.secondary)
            }

            if !recap.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Host")
                        ForEach(Self.columns, id: \.title) { column in
                            Text(column.title).gridColumnAlignment(.trailing)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(recap) { host in
                        GridRow {
                            HStack(spacing: 6) {
                                StatusIcon(status: host.status)
                                Text(host.host)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            ForEach(Self.columns, id: \.title) { column in
                                let value = host.stats[keyPath: column.keyPath]
                                Text("\(value)")
                                    .monospacedDigit()
                                    .foregroundStyle(value == 0 ? Color.secondary.opacity(0.5) : column.color)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
    }

    private struct Column {
        var title: String
        var keyPath: KeyPath<HostStats, Int>
        var color: Color
    }

    private static let columns = [
        Column(title: "OK", keyPath: \.ok, color: .green),
        Column(title: "Changed", keyPath: \.changed, color: .orange),
        Column(title: "Failed", keyPath: \.failed, color: .red),
        Column(title: "Unreachable", keyPath: \.unreachable, color: .red),
        Column(title: "Skipped", keyPath: \.skipped, color: .cyan),
        Column(title: "Rescued", keyPath: \.rescued, color: .primary),
        Column(title: "Ignored", keyPath: \.ignored, color: .primary),
    ]

    private var headline: String {
        let failed = recap.count(where: { $0.stats.failed > 0 || $0.stats.unreachable > 0 })
        let changed = recap.count(where: { $0.stats.changed > 0 })
        var parts = ["\(recap.count) \(recap.count == 1 ? "host" : "hosts")"]
        if changed > 0 { parts.append("\(changed) changed") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Tasks

private struct TaskRow: View {
    let task: RunReport.TaskReport
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(task.results) { result in
                    HostResultView(result: result)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 4)
        } label: {
            HStack(spacing: 8) {
                if let status = task.status {
                    StatusIcon(status: status)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text("\(Text(rolePrefix).foregroundStyle(.secondary))\(task.name)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if task.isHandler {
                    Chip(text: "handler", systemImage: "bell")
                }
                Spacer(minLength: 8)
                counts
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var rolePrefix: String {
        task.role.map { "\($0) › " } ?? ""
    }

    private var counts: some View {
        HStack(spacing: 4) {
            ForEach(Self.shown, id: \.self) { status in
                let count = task.count(status)
                if count > 0 {
                    Chip(text: "\(count) \(status.title.lowercased())", tint: status.color)
                }
            }
            if task.hasDiff {
                Chip(text: "diff", systemImage: "plusminus", tint: .orange)
            }
        }
        .fixedSize()
    }

    private static let shown: [HostStatus] = [.running, .failed, .unreachable, .ignored, .changed, .ok, .skipped]
}

private struct HostResultView: View {
    let result: RunReport.HostResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusIcon(status: result.status)
                Text(result.host)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
                if let delegated = result.delegatedTo {
                    Text("→ \(delegated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(result.status.title)
                    .font(.caption)
                    .foregroundStyle(result.status.color)
                if let items = result.items {
                    Text("\(items) \(items == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rc = result.rc, rc != 0 {
                    Text("exit \(rc)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = result.skipReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let msg = result.msg {
                OutputBlock(text: msg, tint: result.status == .failed || result.status == .unreachable ? .red : nil)
            }
            if let diff = result.diff {
                DiffView(diff: diff)
            }
            if let stderr = result.stderr, result.status == .failed || result.status == .ignored || result.status == .unreachable {
                OutputBlock(title: "stderr", text: stderr, tint: .red)
            }
            if let stdout = result.stdout, result.status == .failed || result.status == .ignored {
                OutputBlock(title: "stdout", text: stdout)
            }
        }
        .padding(.leading, 18)
    }
}

/// Monospaced text in a box, cut to a few lines until expanded.
private struct OutputBlock: View {
    var title: String?
    let text: String
    var tint: Color?

    @State private var showAll = false
    private let maxLines = 12

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = showAll ? text : lines.prefix(maxLines).joined(separator: "\n")

        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(shown)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !showAll && lines.count > maxLines {
                Button("Show \(lines.count - maxLines) more lines") { showAll = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
    }
}

/// A unified diff with added and removed lines colored.
struct DiffView: View {
    let diff: String

    var body: some View {
        Text(Self.attributed(diff))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
    }

    static func attributed(_ diff: String) -> AttributedString {
        var result = AttributedString()
        let lines = diff.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var part = AttributedString(String(line) + (index < lines.count - 1 ? "\n" : ""))
            if let color = color(for: line) {
                part[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
            }
            result += part
        }
        return result
    }

    private static func color(for line: Substring) -> Color? {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return nil
    }
}

// MARK: Status

struct StatusIcon: View {
    let status: HostStatus

    var body: some View {
        Group {
            if status == .running {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(status.color)
            }
        }
        .frame(width: 16)
        .help(status.title)
    }

    private var symbol: String {
        switch status {
        case .running: "circle.dotted"
        case .ok: "checkmark.circle.fill"
        case .changed: "pencil.circle.fill"
        case .skipped: "arrow.right.circle"
        case .ignored: "exclamationmark.circle"
        case .failed: "xmark.circle.fill"
        case .unreachable: "bolt.horizontal.circle.fill"
        }
    }
}

extension HostStatus {
    var color: Color {
        switch self {
        case .running: .accentColor
        case .ok: .green
        case .changed: .orange
        case .skipped: .cyan
        case .ignored: .secondary
        case .failed: .red
        case .unreachable: .red
        }
    }
}
