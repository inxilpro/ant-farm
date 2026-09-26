//
//  RunPlan.swift
//  Ant Farm
//

import Foundation

/// What a run will do before it starts: for each play, the hosts it targets and
/// the tasks it will run, as reported by `ansible-playbook --list-hosts --list-tasks`.
nonisolated struct RunPlan: Equatable, Sendable {
    struct Play: Equatable, Identifiable, Sendable {
        var number: Int
        var name: String
        /// The play's `hosts:` patterns.
        var pattern: [String]
        /// Tags set on the play itself.
        var tags: [String]
        var hosts: [String]
        var tasks: [PlanTask]

        var id: Int { number }
    }

    struct PlanTask: Equatable, Identifiable, Sendable {
        var id: Int
        var name: String
        var role: String?
        var tags: [String]

        /// Dynamic includes are expanded at run time, so their tasks aren't listed.
        var isDynamicInclude: Bool {
            Self.includeActions.contains(name)
        }

        static let includeActions: Set<String> = [
            "include_tasks", "include_role", "include",
            "ansible.builtin.include_tasks", "ansible.builtin.include_role", "ansible.builtin.include",
        ]
    }

    var plays: [Play]

    /// Every host any play targets.
    var hosts: [String] {
        Array(Set(plays.flatMap(\.hosts))).sorted(by: InventoryContents.order)
    }

    /// Every tag on a task that will run.
    var tags: [String] {
        Array(Set(plays.flatMap { $0.tasks.flatMap(\.tags) })).sorted(by: InventoryContents.order)
    }

    var taskCount: Int {
        plays.reduce(0) { $0 + $1.tasks.count }
    }

    var hasDynamicIncludes: Bool {
        plays.contains { $0.tasks.contains(where: \.isDynamicInclude) }
    }

    /// Parses the output of `ansible-playbook --list-hosts --list-tasks`, e.g.
    ///
    ///     play #1 (web): Web servers	TAGS: [webplay]
    ///       pattern: ['web']
    ///       hosts (2):
    ///         web1
    ///         web2
    ///       tasks:
    ///         nginx : Install nginx	TAGS: [nginx]
    static func parse(_ output: String) -> RunPlan {
        enum Section { case none, hosts, tasks }

        var plays: [Play] = []
        var section = Section.none
        var taskID = 0

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                section = .none
                continue
            }

            if let match = line.wholeMatch(of: /play #(\d+) \((.*?)\): (.*)/) {
                let (name, tags) = splitTags(String(match.3))
                plays.append(Play(
                    number: Int(match.1) ?? plays.count + 1,
                    name: name,
                    pattern: [String(match.2)],
                    tags: tags,
                    hosts: [],
                    tasks: []
                ))
                section = .none
                continue
            }

            guard !plays.isEmpty else { continue }
            let index = plays.count - 1

            if line.hasPrefix("pattern: ") {
                let patterns = parseList(String(line.dropFirst("pattern: ".count)))
                if !patterns.isEmpty {
                    plays[index].pattern = patterns
                }
                section = .none
            } else if line.wholeMatch(of: /hosts \(\d+\):/) != nil {
                section = .hosts
            } else if line == "tasks:" {
                section = .tasks
            } else {
                switch section {
                case .hosts:
                    plays[index].hosts.append(line)
                case .tasks:
                    let (title, tags) = splitTags(line)
                    var role: String?
                    var name = title
                    if let separator = title.range(of: " : ") {
                        role = String(title[..<separator.lowerBound])
                        name = String(title[separator.upperBound...])
                    }
                    taskID += 1
                    plays[index].tasks.append(PlanTask(id: taskID, name: name, role: role, tags: tags))
                case .none:
                    break
                }
            }
        }

        for index in plays.indices {
            plays[index].hosts.sort(by: InventoryContents.order)
        }
        return RunPlan(plays: plays)
    }

    /// Splits `name<TAB>TAGS: [a, b]` into the name and its tags.
    private static func splitTags(_ text: String) -> (String, [String]) {
        guard let range = text.range(of: "TAGS: [", options: .backwards) else {
            return (text.trimmingCharacters(in: .whitespaces), [])
        }
        let name = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        let list = text[range.upperBound...].dropLast(text.hasSuffix("]") ? 1 : 0)
        let tags = list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (name, tags)
    }

    /// Parses a Python list literal of strings, e.g. `['web', "db's"]`.
    private static func parseList(_ text: String) -> [String] {
        text.matches(of: /'([^']*)'|"([^"]*)"/).map { String($0.1 ?? $0.2 ?? "") }
    }
}
