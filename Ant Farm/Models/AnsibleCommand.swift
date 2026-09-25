//
//  AnsibleCommand.swift
//  Ant Farm
//

import Foundation

nonisolated enum RunMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case check
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .check: "Check"
        case .live: "Live"
        }
    }
}

/// Everything needed to build an `ansible-playbook` invocation.
///
/// The argv it produces starts with `ansible-playbook` and matches what the
/// ansible-interactive CLI writes to its history file, so both tools share it.
nonisolated struct AnsibleCommand: Equatable, Sendable {
    /// Inventory sources. Empty means Ansible's configured default.
    var inventory: [String] = []
    var playbook: String
    var limit: [String] = []
    var tags: [String] = []
    var skipTags: [String] = []
    var mode: RunMode = .check
    var diff: Bool = true
    var extra: [String] = []

    var argv: [String] {
        var argv = ["ansible-playbook"]
        for source in inventory {
            argv += ["-i", source]
        }
        if mode == .check {
            argv.append("--check")
        }
        if diff {
            argv.append("--diff")
        }
        if !tags.isEmpty {
            argv += ["--tags", tags.joined(separator: ",")]
        }
        if !skipTags.isEmpty {
            argv += ["--skip-tags", skipTags.joined(separator: ",")]
        }
        if !limit.isEmpty {
            argv += ["--limit", limit.joined(separator: ",")]
        }
        argv += extra
        argv.append(playbook)
        return argv
    }

    /// Rebuilds a command from a saved argv. Arguments it doesn't model end up in `extra`.
    init?(argv: [String]) {
        guard argv.first.map({ ($0 as NSString).lastPathComponent == "ansible-playbook" }) == true,
              argv.count >= 2 else { return nil }

        var rest = Array(argv.dropFirst())
        playbook = rest.removeLast()
        mode = .live
        diff = false

        func split(_ value: String) -> [String] {
            value.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
        }

        var index = 0
        while index < rest.count {
            let arg = rest[index]
            let next = index + 1 < rest.count ? rest[index + 1] : nil

            if let (flag, value) = Self.splitEquals(arg) {
                if !apply(flag: flag, value: value, split: split) {
                    extra.append(arg)
                }
                index += 1
                continue
            }

            switch arg {
            case "--check", "-C":
                mode = .check
            case "--diff", "-D":
                diff = true
            case "-i", "--inventory", "--inventory-file", "-t", "--tags", "--skip-tags", "-l", "--limit":
                if let next, apply(flag: arg, value: next, split: split) {
                    index += 1
                } else {
                    extra.append(arg)
                }
            default:
                extra.append(arg)
            }
            index += 1
        }
    }

    init(inventory: [String] = [], playbook: String, limit: [String] = [], tags: [String] = [],
         skipTags: [String] = [], mode: RunMode = .check, diff: Bool = true, extra: [String] = []) {
        self.inventory = inventory
        self.playbook = playbook
        self.limit = limit
        self.tags = tags
        self.skipTags = skipTags
        self.mode = mode
        self.diff = diff
        self.extra = extra
    }

    private mutating func apply(flag: String, value: String, split: (String) -> [String]) -> Bool {
        switch flag {
        case "-i", "--inventory", "--inventory-file": inventory.append(value)
        case "-t", "--tags": tags += split(value)
        case "--skip-tags": skipTags += split(value)
        case "-l", "--limit": limit += split(value)
        default: return false
        }
        return true
    }

    private static func splitEquals(_ arg: String) -> (String, String)? {
        guard arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") else { return nil }
        return (String(arg[..<eq]), String(arg[arg.index(after: eq)...]))
    }
}

nonisolated enum ShellQuoting {
    /// Quotes one argument for display or pasting into a POSIX shell.
    static func quote(_ arg: String) -> String {
        if !arg.isEmpty, arg.range(of: #"^[\w@%+=:,./-]+$"#, options: .regularExpression) != nil {
            return arg
        }
        return "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func format(_ argv: [String]) -> String {
        argv.map(quote).joined(separator: " ")
    }

    /// Splits a string into arguments the way a POSIX shell would, handling
    /// single quotes, double quotes, and backslash escapes. No expansion.
    static func split(_ string: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inArg = false
        var quote: Character?
        var escaping = false

        for char in string {
            if escaping {
                current.append(char)
                escaping = false
                inArg = true
                continue
            }
            if let q = quote {
                if char == q {
                    quote = nil
                } else if char == "\\" && q == "\"" {
                    escaping = true
                } else {
                    current.append(char)
                }
                continue
            }
            switch char {
            case "'", "\"":
                quote = char
                inArg = true
            case "\\":
                escaping = true
            case " ", "\t", "\n":
                if inArg {
                    args.append(current)
                    current = ""
                    inArg = false
                }
            default:
                current.append(char)
                inArg = true
            }
        }
        if inArg {
            args.append(current)
        }
        return args
    }
}
