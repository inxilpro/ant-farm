//
//  Inventory.swift
//  Ant Farm
//

import Foundation

/// An inventory Ant Farm can pass to Ansible with `-i`.
nonisolated struct InventorySource: Hashable, Identifiable, Codable, Sendable {
    /// Paths relative to the workspace. Empty means Ansible's configured default.
    var paths: [String]
    var label: String
    var hint: String?

    var id: String { paths.isEmpty ? "(default)" : paths.joined(separator: "\n") }
    var isDefault: Bool { paths.isEmpty }
}

nonisolated struct InventoryGroup: Hashable, Identifiable, Sendable {
    var name: String
    var hosts: [String]

    var id: String { name }
}

/// The groups and hosts in an inventory, as reported by `ansible-inventory --list`.
nonisolated struct InventoryContents: Equatable, Sendable {
    var groups: [InventoryGroup]
    var hosts: [String]

    static let empty = InventoryContents(groups: [], hosts: [])

    /// Parses the JSON printed by `ansible-inventory --list`.
    static func parse(_ data: Data) throws -> InventoryContents {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AntFarmError.message("ansible-inventory printed something other than a JSON object.")
        }
        return parse(list)
    }

    static func parse(_ list: [String: Any]) -> InventoryContents {
        let groupNames = list.keys.filter { $0 != "_meta" && $0 != "all" }

        func hostsIn(_ name: String, seen: inout Set<String>) -> Set<String> {
            guard !seen.contains(name) else { return [] }
            seen.insert(name)
            let group = list[name] as? [String: Any]
            var hosts = Set(group?["hosts"] as? [String] ?? [])
            for child in group?["children"] as? [String] ?? [] {
                hosts.formUnion(hostsIn(child, seen: &seen))
            }
            return hosts
        }

        func hostsIn(_ name: String) -> Set<String> {
            var seen = Set<String>()
            return hostsIn(name, seen: &seen)
        }

        let groups = groupNames
            .map { InventoryGroup(name: $0, hosts: hostsIn($0).sorted(by: Self.order)) }
            .filter { !$0.hosts.isEmpty }
            .sorted { order($0.name, $1.name) }

        var hosts = Set(((list["_meta"] as? [String: Any])?["hostvars"] as? [String: Any])?.keys.map { $0 } ?? [])
        hosts.formUnion(hostsIn("all"))
        for name in groupNames {
            hosts.formUnion(hostsIn(name))
        }

        return InventoryContents(groups: groups, hosts: hosts.sorted(by: order))
    }

    static func order(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}

nonisolated struct Playbook: Hashable, Identifiable, Codable, Sendable {
    /// Path relative to the workspace.
    var path: String
    /// The first play's name, if it has one.
    var name: String?

    var id: String { path }
}

nonisolated enum AntFarmError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
