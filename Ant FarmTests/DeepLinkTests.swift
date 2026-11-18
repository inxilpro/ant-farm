//
//  DeepLinkTests.swift
//  Ant FarmTests
//

import Foundation
import Testing
@testable import Ant_Farm

struct DeepLinkTests {
    private func link(_ string: String) throws -> DeepLink {
        try DeepLink(url: #require(URL(string: string)))
    }

    @Test func parsesEverySetting() throws {
        let parsed = try link(
            "antfarm://open?repo=internachi/orchestration&folder=./ansible/&inventory=production.ini"
                + "&playbook=ec2-provision.yml&limit=proxy,!proxy-2&tags=nginx-sub-config&skip-tags=slow"
                + "&mode=live&args=-e%20%27env%3Dprod%20east%27"
        )
        #expect(parsed == DeepLink(
            location: .repository("internachi/orchestration", folder: "ansible"),
            inventory: ["production.ini"],
            playbook: "ec2-provision.yml",
            limit: ["proxy", "!proxy-2"],
            tags: ["nginx-sub-config"],
            skipTags: ["slow"],
            mode: .live,
            extraArguments: "-e 'env=prod east'"
        ))
    }

    @Test func acceptsRepeatedAndBracketedKeys() throws {
        let parsed = try link("antfarm://open?path=~/ops&tags[]=a&tags[]=b,c&skip_tags=d&inventory=one.ini&inventory=two.ini")
        #expect(parsed.location == .path("~/ops"))
        #expect(parsed.tags == ["a", "b", "c"])
        #expect(parsed.skipTags == ["d"])
        #expect(parsed.inventory == ["one.ini", "two.ini"])
    }

    @Test func defaultsToCheckModeAndKeepsInventoryAndPlaybook() throws {
        let parsed = try link("antfarm://open?repo=a/b")
        #expect(parsed.mode == .check)
        #expect(parsed.inventory == nil)
        #expect(parsed.playbook == nil)
    }

    @Test func rejectsBadLinks() {
        #expect(throws: DeepLinkError.noLocation) { try link("antfarm://open?playbook=site.yml") }
        #expect(throws: DeepLinkError.unknownAction("run")) { try link("antfarm://run?repo=a/b") }
        #expect(throws: DeepLinkError.unknownMode("yolo")) { try link("antfarm://open?repo=a/b&mode=yolo") }
        #expect(throws: DeepLinkError.notALink) { try link("https://example.com/open?repo=a/b") }
    }

    @Test func roundTripsThroughItsURL() throws {
        let original = DeepLink(
            location: .repository("internachi/orchestration", folder: "ansible"),
            inventory: ["inventories/prod"],
            playbook: "playbooks/site.yml",
            limit: ["web", "!db1"],
            tags: ["deploy"],
            skipTags: ["slow"],
            mode: .live,
            extraArguments: "-e 'a=1 b+c' --forks=5"
        )
        #expect(try DeepLink(url: original.url) == original)
        #expect(!original.url.absoluteString.contains("+"))
    }

    @Test func leavesOutDefaultsWhenBuildingURL() {
        let url = DeepLink(location: .repository("a/b", folder: nil), playbook: "site.yml").url
        #expect(url.absoluteString == "antfarm://open?repo=a/b&playbook=site.yml")
    }
}

struct GitRemoteTests {
    @Test(arguments: [
        "git@github.com:internachi/orchestration.git",
        "https://github.com/internachi/orchestration.git",
        "https://user@github.com/InterNACHI/Orchestration",
        "ssh://git@github.com:22/internachi/orchestration.git",
        "github.com/internachi/orchestration/",
    ])
    func normalizesRemotes(remote: String) {
        #expect(GitRemote.components(remote) == ["github.com", "internachi", "orchestration"])
    }

    @Test func matchesTheEndOfARemote() {
        let remote = "git@github.com:internachi/orchestration.git"
        #expect(GitRemote.matches(remote, repository: "internachi/orchestration"))
        #expect(GitRemote.matches(remote, repository: "github.com/internachi/orchestration"))
        #expect(GitRemote.matches(remote, repository: "https://github.com/internachi/orchestration"))
        #expect(!GitRemote.matches(remote, repository: "other/orchestration"))
        #expect(!GitRemote.matches(remote, repository: "gitlab.com/internachi/orchestration"))
        #expect(!GitRemote.matches(remote, repository: "chestration"))
    }

    @Test func shortNameDropsTheHost() {
        #expect(GitRemote.shortName("git@gitlab.com:group/sub/repo.git") == "group/sub/repo")
    }

    @Test func parsesRemotesFromConfig() {
        let config = """
        [core]
        \trepositoryformatversion = 0
        [remote "origin"]
        \turl = git@github.com:internachi/orchestration.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [remote "fork"]
        \turl = "https://github.com/someone/orchestration"
        [branch "main"]
        \tremote = origin
        """
        #expect(GitRepository.parseRemotes(config) == [
            "origin": "git@github.com:internachi/orchestration.git",
            "fork": "https://github.com/someone/orchestration",
        ])
    }
}

struct DeepLinkResolutionTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "ant-farm-link-tests-\(UUID().uuidString)")

    private func makeClone(_ name: String, remote: String, worktree: Bool = false) throws -> URL {
        let fm = FileManager.default
        let root = base.appending(path: name)
        try fm.createDirectory(at: root.appending(path: "ansible/roles"), withIntermediateDirectories: true)
        let config = "[remote \"origin\"]\n\turl = \(remote)\n"
        if worktree {
            let main = base.appending(path: "\(name)-main/.git")
            try fm.createDirectory(at: main.appending(path: "worktrees/\(name)"), withIntermediateDirectories: true)
            try config.write(to: main.appending(path: "config"), atomically: true, encoding: .utf8)
            try "../..\n".write(to: main.appending(path: "worktrees/\(name)/commondir"), atomically: true, encoding: .utf8)
            try "gitdir: \(main.appending(path: "worktrees/\(name)").path)\n".write(to: root.appending(path: ".git"), atomically: true, encoding: .utf8)
        } else {
            try fm.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
            try config.write(to: root.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func findsTheCloneFromAnyFolderInsideIt() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let other = try makeClone("other", remote: "git@github.com:someone/else.git")
        let clone = try makeClone("orchestration", remote: "git@github.com:internachi/orchestration.git")
        let link = DeepLink(location: .repository("internachi/orchestration", folder: "ansible"))

        let found = link.folders(among: [other, clone.appending(path: "ansible/roles")])

        #expect(found == [clone.appending(path: "ansible").folderURL])
    }

    @Test func readsWorktreeRemotesFromTheMainRepository() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let clone = try makeClone("tree", remote: "https://github.com/internachi/orchestration", worktree: true)
        let link = DeepLink(location: .repository("internachi/orchestration", folder: nil))

        #expect(link.folders(among: [clone]) == [clone.folderURL])
    }

    @Test func skipsAFolderTheCloneDoesNotHave() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let clone = try makeClone("orchestration", remote: "git@github.com:internachi/orchestration.git")
        let link = DeepLink(location: .repository("internachi/orchestration", folder: "missing"))

        #expect(link.folders(among: [clone]).isEmpty)
    }

    @Test func describesTheFolderRelativeToTheRepository() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let clone = try makeClone("orchestration", remote: "git@github.com:internachi/orchestration.git")
        let repository = try #require(GitRepository(containing: clone.appending(path: "ansible")))

        #expect(repository.relativePath(of: clone.appending(path: "ansible")) == "ansible")
        #expect(repository.relativePath(of: clone) == nil)
    }
}
