//
//  RunReport.swift
//  Ant Farm
//

import Foundation

/// One line written by the bundled `antfarm` callback plugin (`Callback/antfarm.py`).
nonisolated struct RunEvent: Decodable, Equatable, Sendable {
    var event: String
    var time: Double?

    var playbook: String?
    var play: String?
    var name: String?
    var pattern: String?

    var task: String?
    var action: String?
    var role: String?
    var handler: Bool?
    var prompts: Bool?

    var host: String?
    var changed: Bool?
    var msg: String?
    var stdout: String?
    var stderr: String?
    var moduleStderr: String?
    var exception: String?
    var skipReason: String?
    var diff: String?
    var rc: Int?
    var items: Int?
    var delegatedTo: String?

    var hosts: [String: HostStats]?

    static func parse(_ line: some StringProtocol) -> RunEvent? {
        try? JSONDecoder().decode(RunEvent.self, from: Data(line.utf8))
    }
}

/// Per-host totals from the play recap.
nonisolated struct HostStats: Codable, Equatable, Sendable {
    var ok = 0
    var changed = 0
    var failed = 0
    var unreachable = 0
    var skipped = 0
    var rescued = 0
    var ignored = 0
}

nonisolated enum HostStatus: String, Equatable, Sendable {
    case running, ok, changed, skipped, ignored, failed, unreachable

    /// Higher is more important when summarizing several results.
    var severity: Int {
        switch self {
        case .skipped: 0
        case .ok: 1
        case .ignored: 2
        case .changed: 3
        case .running: 4
        case .failed: 5
        case .unreachable: 6
        }
    }

    var title: String {
        switch self {
        case .running: "Running"
        case .ok: "OK"
        case .changed: "Changed"
        case .skipped: "Skipped"
        case .ignored: "Failed (ignored)"
        case .failed: "Failed"
        case .unreachable: "Unreachable"
        }
    }
}

/// A run as reported by the callback plugin: plays, tasks, and each host's result.
///
/// Built up one event at a time with `apply(_:)`.
nonisolated struct RunReport: Equatable, Sendable {
    struct HostResult: Equatable, Identifiable, Sendable {
        var host: String
        var status: HostStatus
        var msg: String?
        var stdout: String?
        var stderr: String?
        var skipReason: String?
        var diff: String?
        var rc: Int?
        var items: Int?
        var delegatedTo: String?

        var id: String { host }

        /// Whether there's anything to show beyond the status.
        var hasDetails: Bool {
            diff != nil || msg != nil || stdout != nil || stderr != nil
        }
    }

    struct TaskReport: Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        var role: String?
        var action: String?
        var isHandler: Bool
        var startedAt: Double?
        var results: [HostResult] = []

        /// The most important status among the hosts, or nil before any host starts.
        var status: HostStatus? {
            results.map(\.status).max { $0.severity < $1.severity }
        }

        func count(_ status: HostStatus) -> Int {
            results.count(where: { $0.status == status })
        }

        var needsAttention: Bool {
            results.contains { $0.status == .failed || $0.status == .unreachable }
        }

        var hasDiff: Bool {
            results.contains { $0.diff != nil }
        }

        /// Tasks where nothing changed and nothing failed.
        var isQuiet: Bool {
            results.allSatisfy { $0.status == .ok || $0.status == .skipped }
        }
    }

    struct PlayReport: Equatable, Identifiable, Sendable {
        var id: String
        var name: String
        var pattern: String
        var tasks: [TaskReport] = []
        var noHostsMatched = false
    }

    struct HostRecap: Equatable, Identifiable, Sendable {
        var host: String
        var stats: HostStats

        var id: String { host }

        var status: HostStatus {
            if stats.unreachable > 0 { return .unreachable }
            if stats.failed > 0 { return .failed }
            if stats.changed > 0 { return .changed }
            if stats.ok > 0 { return .ok }
            return .skipped
        }
    }

    var playbook: String?
    var plays: [PlayReport] = []
    /// The recap Ansible printed at the end, once it has.
    var stats: [String: HostStats]?
    /// Ansible is (probably) waiting for someone to type into the terminal.
    var isWaitingForInput = false
    var noHostsRemaining = false

    var hasEvents: Bool {
        playbook != nil || !plays.isEmpty
    }

    var tasks: [TaskReport] {
        plays.flatMap(\.tasks)
    }

    /// The task that started most recently.
    var currentTask: TaskReport? {
        plays.last?.tasks.last
    }

    /// Per-host totals: Ansible's recap when the run has finished, otherwise counted so far.
    var recap: [HostRecap] {
        let totals = stats ?? countedStats
        return totals.map { HostRecap(host: $0.key, stats: $0.value) }
            .sorted { InventoryContents.order($0.host, $1.host) }
    }

    private var countedStats: [String: HostStats] {
        var totals: [String: HostStats] = [:]
        for task in tasks {
            for result in task.results {
                var stats = totals[result.host] ?? HostStats()
                switch result.status {
                case .running: break
                case .ok: stats.ok += 1
                case .changed:
                    stats.ok += 1
                    stats.changed += 1
                case .skipped: stats.skipped += 1
                case .ignored:
                    stats.ok += 1
                    stats.ignored += 1
                case .failed: stats.failed += 1
                case .unreachable: stats.unreachable += 1
                }
                totals[result.host] = stats
            }
        }
        return totals
    }

    mutating func apply(_ event: RunEvent) {
        switch event.event {
        case "vars_prompt":
            isWaitingForInput = true
            return
        case "host_start":
            break
        default:
            isWaitingForInput = false
        }

        switch event.event {
        case "playbook_start":
            playbook = event.playbook

        case "play_start":
            plays.append(PlayReport(
                id: event.play ?? UUID().uuidString,
                name: event.name ?? "",
                pattern: event.pattern ?? ""
            ))

        case "task_start":
            guard let id = event.task else { return }
            if plays.isEmpty {
                plays.append(PlayReport(id: UUID().uuidString, name: "", pattern: ""))
            }
            let play = plays.count - 1
            // Tasks in an include can start more than once; keep one row per task.
            if let index = plays[play].tasks.lastIndex(where: { $0.id == id }) {
                let task = plays[play].tasks.remove(at: index)
                plays[play].tasks.append(task)
            } else {
                plays[play].tasks.append(TaskReport(
                    id: id,
                    name: event.name ?? event.action ?? "",
                    role: event.role,
                    action: event.action,
                    isHandler: event.handler ?? false,
                    startedAt: event.time
                ))
            }
            if event.prompts == true {
                isWaitingForInput = true
            }

        case "host_start":
            guard let host = event.host else { return }
            update(task: event.task) { task in
                if !task.results.contains(where: { $0.host == host }) {
                    task.results.append(HostResult(host: host, status: .running))
                }
            }

        case "ok", "failed", "ignored", "skipped", "unreachable":
            guard let host = event.host else { return }
            let result = HostResult(
                host: host,
                status: status(for: event),
                msg: event.msg,
                stdout: event.stdout,
                stderr: event.stderr ?? event.moduleStderr ?? event.exception,
                skipReason: event.skipReason,
                diff: event.diff,
                rc: event.rc,
                items: event.items,
                delegatedTo: event.delegatedTo
            )
            update(task: event.task) { task in
                if let index = task.results.firstIndex(where: { $0.host == host }) {
                    task.results[index] = result
                } else {
                    task.results.append(result)
                }
            }

        case "no_hosts_matched":
            if !plays.isEmpty {
                plays[plays.count - 1].noHostsMatched = true
            }

        case "no_hosts_remaining":
            noHostsRemaining = true

        case "stats":
            stats = event.hosts ?? [:]

        default:
            break
        }
    }

    private func status(for event: RunEvent) -> HostStatus {
        switch event.event {
        case "failed": .failed
        case "ignored": .ignored
        case "skipped": .skipped
        case "unreachable": .unreachable
        default: event.changed == true ? .changed : .ok
        }
    }

    /// Finds a task by id, searching the latest play first.
    private mutating func update(task id: String?, _ change: (inout TaskReport) -> Void) {
        guard let id else { return }
        for play in plays.indices.reversed() {
            if let index = plays[play].tasks.lastIndex(where: { $0.id == id }) {
                change(&plays[play].tasks[index])
                return
            }
        }
    }

    /// Marks hosts still shown as running as stopped, once the process has exited.
    mutating func finish() {
        isWaitingForInput = false
        for play in plays.indices {
            for task in plays[play].tasks.indices {
                plays[play].tasks[task].results.removeAll { $0.status == .running }
            }
        }
    }
}
