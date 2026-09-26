//
//  PlanView.swift
//  Ant Farm
//

import SwiftUI

/// Before a run: which hosts each play targets and which tasks it will run.
struct PlanView: View {
    let workspace: Workspace

    var body: some View {
        Group {
            if workspace.selectedPlaybook == nil {
                ContentUnavailableView(
                    "No Playbook",
                    systemImage: "doc.questionmark",
                    description: Text("Choose a playbook to see what it will do.")
                )
            } else if let plan = workspace.plan {
                content(plan)
            } else if let error = workspace.planError, !workspace.isLoadingPlan {
                ContentUnavailableView {
                    Label("Couldn't Preview the Run", systemImage: "exclamationmark.triangle")
                } description: {
                    ScrollView {
                        Text(error)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 240)
                } actions: {
                    Button("Try Again") { workspace.schedulePlan() }
                }
            } else {
                ProgressView("Working out what will run…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ plan: RunPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlanSummary(plan: plan, workspace: workspace)
                ForEach(plan.plays) { play in
                    PlanPlayCard(play: play)
                }
                if plan.hasDynamicIncludes || plan.taskCount > 0 {
                    Label(
                        "Tasks with `when:` conditions may be skipped, and tasks inside dynamic includes are only known once the run starts.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if workspace.isLoadingPlan {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
    }
}

private struct PlanSummary: View {
    let plan: RunPlan
    let workspace: Workspace

    private var command: AnsibleCommand? { workspace.command() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                modeLine
            }

            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                row("Playbook") {
                    Text(workspace.selectedPlaybook?.path ?? "")
                        .font(.system(.body, design: .monospaced))
                }
                row("Inventory") {
                    Text(workspace.selectedInventory?.label ?? "Ansible default")
                        .font(.system(.body, design: .monospaced))
                }
                row("Hosts") {
                    if plan.hosts.isEmpty {
                        Label("No hosts match", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        HostChips(hosts: plan.hosts)
                    }
                }
                row("Limit") {
                    if let limit = command?.limit, !limit.isEmpty {
                        patternChips(limit)
                    } else {
                        Text("None — every host each play targets").foregroundStyle(.secondary)
                    }
                }
                row("Tags") {
                    if let tags = command?.tags, !tags.isEmpty {
                        FlowLayout {
                            ForEach(tags, id: \.self) { Chip(text: $0, systemImage: "tag", tint: .accentColor) }
                        }
                    } else {
                        Text("All tags").foregroundStyle(.secondary)
                    }
                }
                if let skipped = command?.skipTags, !skipped.isEmpty {
                    row("Skipping") {
                        FlowLayout {
                            ForEach(skipped, id: \.self) { Chip(text: $0, systemImage: "tag.slash", tint: .red) }
                        }
                    }
                }
                if let extra = command?.extra, !extra.isEmpty {
                    row("Extra") {
                        Text(ShellQuoting.format(extra))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var headline: String {
        let plays = plan.plays.count
        let hosts = plan.hosts.count
        let tasks = plan.taskCount
        return "\(tasks) \(tasks == 1 ? "task" : "tasks") on \(hosts) \(hosts == 1 ? "host" : "hosts") in \(plays) \(plays == 1 ? "play" : "plays")"
    }

    @ViewBuilder
    private var modeLine: some View {
        if workspace.mode == .live {
            Label("Live run: this will make real changes.", systemImage: "bolt.fill")
                .foregroundStyle(.red)
        } else {
            Label("Check mode: reports what would change without changing anything.", systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func patternChips(_ patterns: [String]) -> some View {
        FlowLayout {
            ForEach(patterns, id: \.self) { pattern in
                if pattern.hasPrefix("!") {
                    Chip(text: String(pattern.dropFirst()), systemImage: "minus.circle", tint: .red)
                } else {
                    Chip(text: pattern, systemImage: "checkmark.circle", tint: .accentColor)
                }
            }
        }
    }
}

/// Host names as chips, trimmed to a reasonable number.
struct HostChips: View {
    let hosts: [String]
    var limit = 40
    @State private var showAll = false

    var body: some View {
        let shown = showAll ? hosts : Array(hosts.prefix(limit))
        FlowLayout {
            ForEach(shown, id: \.self) { host in
                Chip(text: host, systemImage: "server.rack")
            }
            if hosts.count > shown.count {
                Button("\(hosts.count - shown.count) more…") { showAll = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

private struct PlanPlayCard: View {
    let play: RunPlan.Play

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(play.name.isEmpty ? "Play \(play.number)" : play.name)
                    .font(.headline)
                Spacer()
                Text("hosts: \(play.pattern.joined(separator: ", "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if play.hosts.isEmpty {
                Label("No hosts match this play, so it will be skipped.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                HostChips(hosts: play.hosts)
            }

            Divider()

            if play.tasks.isEmpty {
                Text("No tasks match the selected tags.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(play.tasks.enumerated()), id: \.element.id) { offset, task in
                        PlanTaskRow(number: offset + 1, task: task)
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
        .opacity(play.hosts.isEmpty ? 0.7 : 1)
    }
}

private struct PlanTaskRow: View {
    let number: Int
    let task: RunPlan.PlanTask

    private var rolePrefix: String {
        task.role.map { "\($0) › " } ?? ""
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 18, alignment: .trailing)

            if task.isDynamicInclude {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.secondary)
                    .help("A dynamic include: its tasks are only known when the run starts.")
            }

            Text("\(Text(rolePrefix).foregroundStyle(.secondary))\(task.name)")
                .lineLimit(2)
                .textSelection(.enabled)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(task.tags, id: \.self) { tag in
                    Chip(text: tag)
                }
            }
            .fixedSize()
        }
    }
}
