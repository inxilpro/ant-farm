//
//  DeepLink.swift
//  Ant Farm
//

import Foundation

/// An `antfarm://open?…` link: a folder, found by its git remote or its path, and the
/// selections to make there. Opening a link never starts a run.
///
///     antfarm://open?repo=internachi/orchestration&inventory=production.ini
///         &playbook=ec2-provision.yml&limit=proxy&tags=nginx-sub-config
///
/// A link describes a whole command, so hosts, tags, skipped tags, and extra arguments it
/// leaves out are cleared, and the mode is Check unless it says `mode=live`. The inventory
/// and playbook stay as they were when it leaves them out.
nonisolated struct DeepLink: Equatable, Sendable {
    static let scheme = "antfarm"
    static let action = "open"

    enum Location: Equatable, Sendable {
        /// A clone of a git repository, wherever it is on this Mac, and a folder inside it.
        case repository(String, folder: String?)
        /// A folder on disk. A leading `~` is the home folder.
        case path(String)
    }

    var location: Location
    /// Inventory sources, as `-i` takes them, relative to the folder.
    var inventory: [String]?
    var playbook: String?
    /// Hosts and groups. A leading `!` excludes one.
    var limit: [String] = []
    var tags: [String] = []
    var skipTags: [String] = []
    var mode: RunMode = .check
    /// More `ansible-playbook` arguments, written as on a command line.
    var extraArguments = ""

    init(location: Location, inventory: [String]? = nil, playbook: String? = nil, limit: [String] = [],
         tags: [String] = [], skipTags: [String] = [], mode: RunMode = .check, extraArguments: String = "") {
        self.location = location
        self.inventory = inventory
        self.playbook = playbook
        self.limit = limit
        self.tags = tags
        self.skipTags = skipTags
        self.mode = mode
        self.extraArguments = extraArguments
    }

    static func handles(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    init(url: URL) throws(DeepLinkError) {
        guard Self.handles(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw .notALink
        }
        guard (components.host ?? "").lowercased() == Self.action else {
            throw .unknownAction(components.host ?? "")
        }

        var values: [String: [String]] = [:]
        for item in components.queryItems ?? [] {
            // Accept `tags[]=a&tags[]=b` too, as web frameworks write repeated keys.
            var key = item.name.lowercased().replacingOccurrences(of: "_", with: "-")
            if key.hasSuffix("[]") {
                key.removeLast(2)
            }
            values[key, default: []].append(item.value ?? "")
        }

        func one(_ key: String) -> String? {
            values[key]?.last.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }

        // Each value may be repeated, comma-separated, or both, like Ansible's own flags.
        func list(_ key: String) -> [String] {
            (values[key] ?? [])
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        if let repo = one("repo") {
            location = .repository(repo, folder: one("folder").map(Self.normalize).flatMap { $0.isEmpty ? nil : $0 })
        } else if let path = one("path") {
            location = .path(path)
        } else {
            throw .noLocation
        }

        let inventory = (values["inventory"] ?? []).map(Self.normalize).filter { !$0.isEmpty }
        self.inventory = inventory.isEmpty ? nil : inventory
        playbook = one("playbook").map(Self.normalize)
        limit = list("limit")
        tags = list("tags")
        skipTags = list("skip-tags")
        extraArguments = one("args") ?? ""

        switch one("mode")?.lowercased() {
        case nil, "check": mode = .check
        case "live": mode = .live
        case let other?: throw .unknownMode(other)
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.action
        var items: [URLQueryItem] = []
        switch location {
        case let .repository(repo, folder):
            items.append(URLQueryItem(name: "repo", value: repo))
            if let folder {
                items.append(URLQueryItem(name: "folder", value: folder))
            }
        case let .path(path):
            items.append(URLQueryItem(name: "path", value: path))
        }
        for source in inventory ?? [] {
            items.append(URLQueryItem(name: "inventory", value: source))
        }
        if let playbook {
            items.append(URLQueryItem(name: "playbook", value: playbook))
        }
        if !limit.isEmpty {
            items.append(URLQueryItem(name: "limit", value: limit.joined(separator: ",")))
        }
        if !tags.isEmpty {
            items.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        if !skipTags.isEmpty {
            items.append(URLQueryItem(name: "skip-tags", value: skipTags.joined(separator: ",")))
        }
        if mode == .live {
            items.append(URLQueryItem(name: "mode", value: "live"))
        }
        if !extraArguments.isEmpty {
            items.append(URLQueryItem(name: "args", value: extraArguments))
        }
        components.queryItems = items
        // URLComponents leaves `+` alone, but browsers and other apps read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// One spelling per relative path, so `./site.yml` and `site.yml/` match `site.yml`.
    static func normalize(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path == "." ? "" : path
    }

    // MARK: Finding the folder

    /// The folders on this Mac the link could mean, best first. Candidates are folders Ant
    /// Farm knows (open windows, then recent folders); a repository link matches any of them
    /// inside a clone of that repository.
    func folders(among candidates: [URL]) -> [URL] {
        var found: [URL] = []
        func add(_ url: URL) {
            let url = url.folderURL
            if url.isFolder && !found.contains(url) {
                found.append(url)
            }
        }

        switch location {
        case let .path(path):
            add(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        case let .repository(repo, folder):
            for candidate in candidates {
                guard let repository = GitRepository(containing: candidate),
                      repository.remotes.values.contains(where: { GitRemote.matches($0, repository: repo) })
                else { continue }
                add(folder.map { repository.root.appending(path: $0) } ?? repository.root)
            }
        }
        return found
    }
}

nonisolated enum DeepLinkError: LocalizedError, Equatable {
    case notALink
    case unknownAction(String)
    case noLocation
    case unknownMode(String)

    var errorDescription: String? {
        switch self {
        case .notALink: "This isn’t an Ant Farm link."
        case .unknownAction(let action): "Ant Farm doesn’t know how to “\(action)”. Links start with antfarm://open."
        case .noLocation: "The link doesn’t say which folder to open. It needs a repo or a path."
        case .unknownMode(let mode): "“\(mode)” isn’t a mode. Use check or live."
        }
    }
}
