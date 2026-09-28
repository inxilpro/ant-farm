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
                let running = plan.plays.filter(\.willRun)
                let skipped = plan.plays.filter { !$0.willRun }
                if running.isEmpty {
                    Label(noMatchMessage, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 10))
                }
                ForEach(running) { play in
                    PlanPlayCard(play: play)
                }
                if !running.isEmpty && !skipped.isEmpty {
                    Text("Not Running")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ForEach(skipped) { play in
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

    private var noMatchMessage: String {
        let command = workspace.command()
        let hasTags = !(command?.tags.isEmpty ?? true) || !(command?.skipTags.isEmpty ?? true)
        let hasLimit = !(command?.limit.isEmpty ?? true)
        switch (hasTags, hasLimit) {
        case (true, true): return "No plays match the hosts and tags you've selected"
        case (true, false): return "No plays match the tags you've selected"
        case (false, true): return "No plays match the hosts you've selected"
        case (false, false): return "No plays have hosts and tasks to run"
        }
    }
}

private extension RunPlan.Play {
    /// Whether the play has hosts to run on and tasks to run there.
    var willRun: Bool { !hosts.isEmpty && !tasks.isEmpty }
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
        .opacity(play.willRun ? 1 : 0.7)
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

            TagStack(tags: task.tags)
        }
    }
}

/// A task's tags. More than a couple collapse into a stack that fans out on hover.
private struct TagStack: View {
    let tags: [String]
    var collapseAfter = 2
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if tags.count <= collapseAfter {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        Chip(text: tag)
                    }
                }
            } else {
                TagFanLayout(fanned: isHovering ? 1 : 0) {
                    ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                        Chip(text: tag)
                            .background(Color(nsColor: .controlBackgroundColor), in: .capsule)
                            // Stacked, the tags behind the first are shaded so their edges show.
                            .overlay(Capsule().fill(Color.secondary.opacity(index == 0 || isHovering ? 0 : 0.14)))
                            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
                            // The first tag sits on top of the stack.
                            .zIndex(Double(tags.count - index))
                    }
                    Text("+\(tags.count - 1)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .opacity(isHovering ? 0 : 1)
                }
            }
        }
        .fixedSize()
        .contentShape(Rectangle())
        .help(tags.joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.count == 1 ? "Tag" : "Tags")
        .accessibilityValue(tags.joined(separator: ", "))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isHovering)
    }
}

/// Lays tags out as a stack, each peeking out behind the first, or fanned out in a row
/// that still overlaps a little. `fanned` runs from 0 to 1, so the change animates.
/// The last subview is the "+N" count, which follows the stack's trailing edge.
private struct TagFanLayout: Layout, Animatable {
    var fanned: CGFloat

    var animatableData: CGFloat {
        get { fanned }
        set { fanned = newValue }
    }

    /// How far each tag behind the first peeks out, and how many of them show.
    private let peek: CGFloat = 4
    private let maxLayers = 3
    /// How much neighbouring tags overlap when fanned out.
    private let overlap: CGFloat = 3
    private let countSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews)) {
            // Pinned by the trailing edge: a tag narrower than the first still peeks out behind it.
            subview.place(
                at: CGPoint(x: bounds.minX + frame.maxX, y: bounds.midY),
                anchor: .trailing,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews) -> [CGRect] {
        guard subviews.count > 1 else { return [] }
        let chips = subviews.dropLast().map { $0.sizeThatFits(.unspecified) }
        let count = subviews[subviews.count - 1].sizeThatFits(.unspecified)
        let front = chips[0].width

        var frames: [CGRect] = []
        var fannedX: CGFloat = 0
        for (index, size) in chips.enumerated() {
            // Stacked, a tag behind the first is at most the first's width and shows only its edge.
            let layer = CGFloat(min(index, maxLayers))
            let stackedWidth = index == 0 ? size.width : front
            let stackedX = layer * peek
            let x = stackedX + (fannedX - stackedX) * fanned
            let width = stackedWidth + (size.width - stackedWidth) * fanned
            frames.append(CGRect(x: x, y: 0, width: width, height: size.height))
            fannedX += size.width - overlap
        }

        let stackEnd = front + CGFloat(min(chips.count - 1, maxLayers)) * peek
        let fannedEnd = fannedX + overlap
        let countX = stackEnd + countSpacing
        // Fanned out, the count has faded and the row ends at the last tag.
        let end = (countX + count.width) + (fannedEnd - (countX + count.width)) * fanned
        frames.append(CGRect(x: min(countX, end - count.width), y: 0, width: count.width, height: count.height))
        return frames
    }
}
