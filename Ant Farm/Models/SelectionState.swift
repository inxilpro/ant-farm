//
//  SelectionState.swift
//  Ant Farm
//

import Foundation

/// A row in the inventory or tag list can be included, excluded, or left alone.
nonisolated enum SelectionState: String, Codable, Sendable {
    case none
    case included
    case excluded

    /// What a plain click does: toggle inclusion, and clear an exclusion.
    var toggled: SelectionState {
        self == .none ? .included : .none
    }
}

/// Included and excluded names, kept in the order they were chosen.
nonisolated struct Selection: Equatable, Codable, Sendable {
    private(set) var included: [String] = []
    private(set) var excluded: [String] = []

    var isEmpty: Bool { included.isEmpty && excluded.isEmpty }

    func state(of name: String) -> SelectionState {
        if included.contains(name) { return .included }
        if excluded.contains(name) { return .excluded }
        return .none
    }

    mutating func set(_ name: String, to state: SelectionState) {
        included.removeAll { $0 == name }
        excluded.removeAll { $0 == name }
        switch state {
        case .included: included.append(name)
        case .excluded: excluded.append(name)
        case .none: break
        }
    }

    mutating func removeAll() {
        included = []
        excluded = []
    }

    /// Drops names that no longer exist.
    mutating func keep(only names: Set<String>) {
        included.removeAll { !names.contains($0) }
        excluded.removeAll { !names.contains($0) }
    }

    /// Ansible `--limit` patterns: included names, then `!name` for exclusions.
    var limitPatterns: [String] {
        included + excluded.map { "!" + $0 }
    }

    init(included: [String] = [], excluded: [String] = []) {
        self.included = included
        self.excluded = excluded
    }

    init(limitPatterns: [String]) {
        for pattern in limitPatterns {
            if pattern.hasPrefix("!") {
                excluded.append(String(pattern.dropFirst()))
            } else {
                included.append(pattern)
            }
        }
    }
}
