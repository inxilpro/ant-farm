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
    /// Every host in the group, including those in its child groups.
    var hosts: [String]
    /// The names of the groups directly inside this one.
    var children: [String] = []

    var id: String { name }
}

/// One place a group appears in the group tree. A group with several parents appears once under each.
nonisolated struct InventoryGroupNode: Hashable, Identifiable, Sendable {
    /// Group names from the top level down to this group.
    var id: [String]
    var group: InventoryGroup
    var children: [InventoryGroupNode]
}

/// The groups and hosts in an inventory, as reported by `ansible-inventory --list`.
nonisolated struct InventoryContents: Equatable, Sendable {
    var groups: [InventoryGroup]
    var hosts: [String]
    /// The names of the top-level groups (the children of `all`).
    var roots: [String] = []

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

        func collectHosts(_ name: String, seen: inout Set<String>) -> Set<String> {
            guard !seen.contains(name) else { return [] }
            seen.insert(name)
            let group = list[name] as? [String: Any]
            var hosts = Set(group?["hosts"] as? [String] ?? [])
            for child in group?["children"] as? [String] ?? [] {
                hosts.formUnion(collectHosts(child, seen: &seen))
            }
            return hosts
        }

        func hostsIn(_ name: String) -> Set<String> {
            var seen = Set<String>()
            return collectHosts(name, seen: &seen)
        }

        func childNames(_ name: String) -> [String] {
            (list[name] as? [String: Any])?["children"] as? [String] ?? []
        }

        var groups = groupNames
            .map { InventoryGroup(name: $0, hosts: hostsIn($0).sorted(by: Self.order)) }
            .filter { !$0.hosts.isEmpty }
            .sorted { order($0.name, $1.name) }
        let known = Set(groups.map(\.name))
        for index in groups.indices {
            groups[index].children = childNames(groups[index].name)
                .filter { known.contains($0) }
                .sorted(by: order)
        }

        var hosts = Set(((list["_meta"] as? [String: Any])?["hostvars"] as? [String: Any])?.keys.map { $0 } ?? [])
        hosts.formUnion(hostsIn("all"))
        for name in groupNames {
            hosts.formUnion(hostsIn(name))
        }

        // Top-level groups are the children of `all`. Anything the tree doesn't reach
        // (no `all` entry, or a cycle) is added at the top level so it stays visible.
        var roots = childNames("all").filter { known.contains($0) }
        if list["all"] == nil {
            let nested = Set(groups.flatMap(\.children))
            roots = groups.map(\.name).filter { !nested.contains($0) }
        }
        var reached = Set<String>()
        func reach(_ name: String) {
            guard reached.insert(name).inserted else { return }
            childNames(name).forEach(reach)
        }
        roots.forEach(reach)
        for group in groups where !reached.contains(group.name) {
            roots.append(group.name)
            reach(group.name)
        }
        roots.sort { a, b in
            // Ansible's catch-all group reads best at the end.
            (a == "ungrouped") != (b == "ungrouped") ? b == "ungrouped" : order(a, b)
        }

        return InventoryContents(groups: groups, hosts: hosts.sorted(by: order), roots: roots)
    }

    /// The groups as a tree, keeping a group when its name or one of its hosts passes
    /// `include`, or when it contains a group that is kept.
    func groupTree(including include: (String) -> Bool = { _ in true }) -> [InventoryGroupNode] {
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        func build(_ name: String, path: [String]) -> InventoryGroupNode? {
            guard let group = byName[name], !path.contains(name) else { return nil }
            let id = path + [name]
            let children = group.children.compactMap { build($0, path: id) }
            guard include(name) || group.hosts.contains(where: include) || !children.isEmpty else { return nil }
            return InventoryGroupNode(id: id, group: group, children: children)
        }

        return roots.compactMap { build($0, path: []) }
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
