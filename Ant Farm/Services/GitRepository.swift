//
//  GitRepository.swift
//  Ant Farm
//

import Foundation

/// The git repository a folder is in, read from its config file. Reading the file rather
/// than running `git` keeps this fast enough to check every recent folder when a link opens.
nonisolated struct GitRepository: Sendable {
    /// The top of the working tree.
    var root: URL
    /// Remote names and their URLs.
    var remotes: [String: String]

    init?(containing folder: URL) {
        let fm = FileManager.default
        var current = folder.folderURL
        while true {
            let dotGit = current.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                guard let gitDirectory = isDirectory.boolValue ? dotGit : Self.linkedGitDirectory(dotGit, in: current) else { return nil }
                root = current
                remotes = Self.remotes(in: Self.commonDirectory(of: gitDirectory))
                return
            }
            let parent = current.deletingLastPathComponent().folderURL
            guard parent != current else { return nil }
            current = parent
        }
    }

    /// The remote a shared link should name: `origin` when there is one.
    var preferredRemote: String? {
        remotes["origin"] ?? remotes.sorted { $0.key < $1.key }.first?.value
    }

    /// The path from the top of the working tree to a folder inside it, or nil for the top itself.
    func relativePath(of folder: URL) -> String? {
        let rootPath = root.folderURL.path
        let path = folder.folderURL.path
        guard path.hasPrefix(rootPath), path != rootPath else { return nil }
        return DeepLink.normalize(String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// Worktrees and submodules have a `.git` file that points at the real git folder.
    private static func linkedGitDirectory(_ file: URL, in folder: URL) -> URL? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8),
              let line = contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appending(path: path)
    }

    /// A worktree's own git folder keeps its config in the main repository's.
    private static func commonDirectory(of gitDirectory: URL) -> URL {
        guard let contents = try? String(contentsOf: gitDirectory.appending(path: "commondir"), encoding: .utf8) else {
            return gitDirectory
        }
        let path = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : gitDirectory.appending(path: path)
    }

    private static func remotes(in gitDirectory: URL) -> [String: String] {
        guard let config = try? String(contentsOf: gitDirectory.appending(path: "config"), encoding: .utf8) else { return [:] }
        return parseRemotes(config)
    }

    /// The `url` of each `[remote "name"]` section in a git config file.
    static func parseRemotes(_ config: String) -> [String: String] {
        var remotes: [String: String] = [:]
        var section: String?
        for line in config.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.firstMatch(of: /^\[\s*remote\s+"(.+)"\s*\]/).map { String($0.1) }
            } else if let section, remotes[section] == nil,
                      let match = line.firstMatch(of: /^url\s*=\s*(.+)$/) {
                remotes[section] = match.1.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
            }
        }
        return remotes
    }
}

/// Compares git remotes however they're written: SSH, scp-style, HTTPS, or just `owner/name`.
nonisolated enum GitRemote {
    /// Host and path segments, lowercased, without a user, port, or `.git`.
    /// `git@github.com:internachi/orchestration.git` is `github.com/internachi/orchestration`.
    static func components(_ remote: String) -> [String] {
        var rest = remote.trimmingCharacters(in: .whitespaces).lowercased()
        let hasScheme: Bool
        if let range = rest.range(of: #"^[a-z][a-z0-9+.-]*://"#, options: .regularExpression) {
            rest.removeSubrange(range)
            hasScheme = true
        } else {
            hasScheme = false
        }
        let hostEnd = rest.firstIndex(of: "/") ?? rest.endIndex
        if let at = rest[..<hostEnd].lastIndex(of: "@") {
            rest.removeSubrange(...at)
        }
        if let colon = rest.firstIndex(of: ":"), colon < (rest.firstIndex(of: "/") ?? rest.endIndex) {
            if hasScheme {
                // A port, as in ssh://git@host:22/owner/name.
                let portEnd = rest[colon...].firstIndex(of: "/") ?? rest.endIndex
                rest.removeSubrange(colon..<portEnd)
            } else {
                // scp-style: host:owner/name.
                rest.replaceSubrange(colon...colon, with: "/")
            }
        }
        var parts = rest.split(separator: "/").map(String.init)
        if let last = parts.last, last.hasSuffix(".git") {
            parts[parts.count - 1] = String(last.dropLast(4))
        }
        return parts.filter { !$0.isEmpty }
    }

    /// Whether a remote is the repository a link names. The link may leave out the host
    /// (`internachi/orchestration`), so it matches the end of the remote.
    static func matches(_ remote: String, repository: String) -> Bool {
        let remote = components(remote)
        let wanted = components(repository)
        return !wanted.isEmpty && wanted.count <= remote.count && Array(remote.suffix(wanted.count)) == wanted
    }

    /// How a shared link names a remote: its path without the host, such as `internachi/orchestration`.
    static func shortName(_ remote: String) -> String {
        let parts = components(remote)
        return (parts.count > 1 ? parts.dropFirst() : parts[...]).joined(separator: "/")
    }
}
