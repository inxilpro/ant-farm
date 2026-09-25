//
//  AnsibleTools.swift
//  Ant Farm
//

import Foundation

/// Where the Ansible executables live, and the environment to run them in.
///
/// Apps launched from the Finder get a minimal PATH, so Ant Farm borrows the
/// user's login shell environment (where Homebrew, pipx, and friends add
/// themselves) and looks for Ansible there.
nonisolated struct AnsibleTools: Sendable {
    var playbook: URL
    var inventory: URL
    var config: URL
    var environment: [String: String]

    /// Environment for runs shown in the terminal: forces color output.
    var terminalEnvironment: [String: String] {
        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["ANSIBLE_FORCE_COLOR"] = "1"
        env["PY_COLORS"] = "1"
        env.removeValue(forKey: "NO_COLOR")
        return env
    }

    static let fallbackDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.local/bin",
        "/opt/local/bin",
        "/usr/bin",
    ]

    /// Finds the Ansible executables. `overrideDirectory` (from Settings) wins when set.
    static func locate(environment: [String: String], overrideDirectory: String?) -> AnsibleTools? {
        var directories: [String] = []
        if let overrideDirectory, !overrideDirectory.isEmpty {
            directories.append(overrideDirectory)
        } else {
            directories += (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            directories += fallbackDirectories
        }

        let fm = FileManager.default
        for directory in directories {
            let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
            let playbook = dir.appending(path: "ansible-playbook")
            guard fm.isExecutableFile(atPath: playbook.path) else { continue }

            var env = environment
            // Make sure the helpers Ansible spawns (python, ssh) resolve the same way.
            let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            if !path.split(separator: ":").contains(Substring(dir.path)) {
                env["PATH"] = dir.path + ":" + path
            }
            return AnsibleTools(
                playbook: playbook,
                inventory: dir.appending(path: "ansible-inventory"),
                config: dir.appending(path: "ansible-config"),
                environment: env
            )
        }
        return nil
    }
}

nonisolated enum LoginShell {
    private static let marker = "__ANT_FARM_ENV__"

    /// Reads the environment of the user's login shell, falling back to this process's environment.
    static func environment() async -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        let shell = current["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"

        do {
            let result = try await ProcessRunner.run(
                URL(fileURLWithPath: shell),
                arguments: ["-l", "-i", "-c", "printf '%s' \(marker); /usr/bin/env -0"],
                in: FileManager.default.homeDirectoryForCurrentUser,
                timeout: 10
            )
            guard let parsed = parse(result.stdout), parsed["PATH"] != nil else { return current }
            return parsed
        } catch {
            return current
        }
    }

    /// Parses `env -0` output that follows the marker (shell startup files may print before it).
    static func parse(_ data: Data) -> [String: String]? {
        let output = String(decoding: data, as: UTF8.self)
        guard let range = output.range(of: marker) else { return nil }
        var env: [String: String] = [:]
        for entry in output[range.upperBound...].split(separator: "\0") {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return env.isEmpty ? nil : env
    }
}
