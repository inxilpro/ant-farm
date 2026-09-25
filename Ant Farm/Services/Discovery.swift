//
//  Discovery.swift
//  Ant Farm
//

import Foundation
import Yams

/// Finds inventories, playbooks, and tags in a workspace, following the same
/// rules as the ansible-interactive CLI.
nonisolated enum Discovery {
    static let maxFileSize = 5 * 1024 * 1024
    static let playbookDirectories = [".", "playbooks"]
    static let importKeys = ["import_playbook", "ansible.builtin.import_playbook"]

    // MARK: Inventories

    /// Ansible's configured default inventory (ansible.cfg or ANSIBLE_INVENTORY), if one is set.
    @concurrent
    static func configuredInventory(in directory: URL, tools: AnsibleTools) async -> InventorySource? {
        guard let result = try? await ProcessRunner.run(
            tools.config,
            arguments: ["dump", "--only-changed", "--format", "json"],
            in: directory,
            environment: tools.environment
        ), result.status == 0 else { return nil }
        return parseConfigDump(result.stdout, relativeTo: directory)
    }

    static func parseConfigDump(_ data: Data, relativeTo directory: URL) -> InventorySource? {
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let setting = settings.first(where: { $0["name"] as? String == "DEFAULT_HOST_LIST" }),
              let paths = setting["value"] as? [String], !paths.isEmpty
        else { return nil }

        let origin = (setting["origin"] as? String)?.hasPrefix("env:") == true ? "ANSIBLE_INVENTORY" : "ansible.cfg"
        let label = paths.map { relativePath($0, to: directory) }.joined(separator: ", ")
        return InventorySource(paths: [], label: label, hint: "Default from \(origin)")
    }

    /// Files and directories in the workspace root that look like inventories.
    @concurrent
    static func inventories(in directory: URL) async -> [InventorySource] {
        let fm = FileManager.default
        var sources: [InventorySource] = []

        for name in list(directory) {
            let url = directory.appending(path: name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                if name == "inventory" {
                    sources.append(InventorySource(paths: [name], label: name, hint: "Directory"))
                } else if name == "inventories" {
                    for child in list(url) {
                        let childURL = url.appending(path: child)
                        let path = "\(name)/\(child)"
                        var childIsDirectory: ObjCBool = false
                        guard fm.fileExists(atPath: childURL.path, isDirectory: &childIsDirectory) else { continue }
                        if childIsDirectory.boolValue {
                            sources.append(InventorySource(paths: [path], label: path, hint: "Directory"))
                        } else if looksLikeInventoryFile(childURL) {
                            sources.append(InventorySource(paths: [path], label: path))
                        }
                    }
                }
                continue
            }

            if looksLikeInventoryFile(url) {
                sources.append(InventorySource(paths: [name], label: name))
            }
        }
        return sources
    }

    static func looksLikeInventoryFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard !name.hasPrefix("."), name != "ansible.cfg" else { return false }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileSize,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return false }

        switch ext {
        case "yml", "yaml": return looksLikeYamlInventory(contents)
        case "", "ini": return looksLikeIniInventory(name: name, contents: contents)
        default: return false
        }
    }

    static func looksLikeIniInventory(name: String, contents: String) -> Bool {
        guard !contents.contains("\0") else { return false }
        // A group header like [web] or [web:children]
        if contents.range(of: #"(?m)^\s*\[[^\]\s]+\]\s*$"#, options: .regularExpression) != nil {
            return true
        }
        // Files without sections only count when they're named like an inventory.
        return ["hosts", "inventory"].contains(name.lowercased())
    }

    static func looksLikeYamlInventory(_ contents: String) -> Bool {
        guard let data = (try? Yams.load(yaml: contents)) as? [String: Any] else { return false }

        // Inventory plugin config, e.g. aws_ec2.yml
        if data["plugin"] is String {
            return true
        }

        let groups = Array(data.values)
        return !groups.isEmpty
            && groups.allSatisfy { $0 is NSNull || $0 is [String: Any] }
            && groups.contains { group in
                guard let group = group as? [String: Any] else { return false }
                return group["hosts"] != nil || group["children"] != nil || group["vars"] != nil
            }
    }

    /// Loads groups and hosts with `ansible-inventory --list`.
    @concurrent
    static func contents(of source: InventorySource, in directory: URL, tools: AnsibleTools) async throws -> InventoryContents {
        let args = source.paths.flatMap { ["-i", $0] } + ["--list"]
        let result = try await ProcessRunner.run(tools.inventory, arguments: args, in: directory, environment: tools.environment)
        guard result.status == 0 else {
            throw AntFarmError.message(failure("ansible-inventory", result))
        }
        let contents = try InventoryContents.parse(result.stdout)
        if contents.hosts.isEmpty {
            throw AntFarmError.message("No hosts found in \(source.isDefault ? "the default inventory" : source.label).")
        }
        return contents
    }

    // MARK: Playbooks

    /// YAML files in the workspace root and ./playbooks that contain plays.
    @concurrent
    static func playbooks(in directory: URL) async -> [Playbook] {
        var playbooks: [Playbook] = []
        for subdirectory in playbookDirectories {
            let dir = subdirectory == "." ? directory : directory.appending(path: subdirectory)
            for name in list(dir) where ["yml", "yaml"].contains((name as NSString).pathExtension.lowercased()) {
                let path = subdirectory == "." ? name : "\(subdirectory)/\(name)"
                let url = dir.appending(path: name)
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileSize,
                      let contents = try? String(contentsOf: url, encoding: .utf8),
                      let playbook = parsePlaybook(path: path, contents: contents)
                else { continue }
                playbooks.append(playbook)
            }
        }
        return playbooks
    }

    static func parsePlaybook(path: String, contents: String) -> Playbook? {
        guard let plays = (try? Yams.load(yaml: contents)) as? [Any], !plays.isEmpty else { return nil }
        let isPlay: (Any) -> Bool = { item in
            guard let item = item as? [String: Any] else { return false }
            return item["hosts"] != nil || importKeys.contains { item[$0] != nil }
        }
        guard plays.allSatisfy(isPlay) else { return nil }
        return Playbook(path: path, name: (plays.first as? [String: Any])?["name"] as? String)
    }

    // MARK: Tags

    /// Every tag a playbook uses, via `ansible-playbook --list-tags`.
    @concurrent
    static func tags(for playbook: Playbook, inventory: InventorySource?, in directory: URL, tools: AnsibleTools) async throws -> [String] {
        let args = (inventory?.paths ?? []).flatMap { ["-i", $0] } + ["--list-tags", playbook.path]
        let result = try await ProcessRunner.run(tools.playbook, arguments: args, in: directory, environment: tools.environment)
        guard result.status == 0 else {
            throw AntFarmError.message(failure("ansible-playbook --list-tags", result))
        }
        return parseListTags(result.output)
    }

    /// Parses `--list-tags` output, e.g. `TASK TAGS: [deploy, nginx, setup]`.
    static func parseListTags(_ output: String) -> [String] {
        var tags = Set<String>()
        let regex = /TAGS: \[([^\]]*)\]/
        for match in output.matches(of: regex) {
            for tag in match.1.split(separator: ",") {
                let trimmed = tag.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { tags.insert(trimmed) }
            }
        }
        return tags.sorted(by: InventoryContents.order)
    }

    // MARK: Helpers

    static func list(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted(by: InventoryContents.order)
    }

    static func relativePath(_ path: String, to directory: URL) -> String {
        let base = directory.standardizedFileURL.path
        let full = URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL.path
        if full.hasPrefix(base + "/") {
            return String(full.dropFirst(base.count + 1))
        }
        return path
    }

    static func failure(_ command: String, _ result: ProcessResult) -> String {
        let detail = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = detail.isEmpty ? fallback : detail
        return "\(command) exited with status \(result.status)." + (text.isEmpty ? "" : "\n\n" + text)
    }
}
