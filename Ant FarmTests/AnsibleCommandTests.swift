//
//  AnsibleCommandTests.swift
//  Ant FarmTests
//

import Testing
@testable import Ant_Farm

struct AnsibleCommandTests {
    @Test func buildsCheckCommandLikeTheCLI() {
        let command = AnsibleCommand(
            inventory: ["inventory"],
            playbook: "site.yml",
            limit: ["web", "!db1"],
            tags: ["deploy", "nginx"],
            mode: .check
        )
        #expect(command.argv == [
            "ansible-playbook", "-i", "inventory", "--check", "--diff",
            "--tags", "deploy,nginx", "--limit", "web,!db1", "site.yml",
        ])
    }

    @Test func buildsLiveCommandWithSkipTagsAndExtras() {
        let command = AnsibleCommand(
            playbook: "playbooks/deploy.yml",
            skipTags: ["slow"],
            mode: .live,
            diff: false,
            extra: ["-e", "env=staging"]
        )
        #expect(command.argv == [
            "ansible-playbook", "--skip-tags", "slow", "-e", "env=staging", "playbooks/deploy.yml",
        ])
    }

    @Test func roundTripsThroughArgv() throws {
        let original = AnsibleCommand(
            inventory: ["inventories/prod", "extra.ini"],
            playbook: "site.yml",
            limit: ["web"],
            tags: ["a", "b"],
            skipTags: ["c"],
            mode: .check,
            extra: ["--ask-become-pass"]
        )
        let parsed = try #require(AnsibleCommand(argv: original.argv))
        #expect(parsed == original)
    }

    @Test func parsesEqualsFormAndShortFlags() throws {
        let parsed = try #require(AnsibleCommand(argv: [
            "ansible-playbook", "--tags=a,b", "-l", "web", "-C", "-v", "site.yml",
        ]))
        #expect(parsed.tags == ["a", "b"])
        #expect(parsed.limit == ["web"])
        #expect(parsed.mode == .check)
        #expect(parsed.diff == false)
        #expect(parsed.extra == ["-v"])
        #expect(parsed.playbook == "site.yml")
    }

    @Test func rejectsOtherCommands() {
        #expect(AnsibleCommand(argv: ["ansible", "all", "-m", "ping"]) == nil)
        #expect(AnsibleCommand(argv: ["ansible-playbook"]) == nil)
    }
}

struct ShellQuotingTests {
    @Test func quotesOnlyWhenNeeded() {
        #expect(ShellQuoting.quote("site.yml") == "site.yml")
        #expect(ShellQuoting.quote("web,!db") == "'web,!db'")
        #expect(ShellQuoting.quote("it's") == #"'it'\''s'"#)
        #expect(ShellQuoting.quote("") == "''")
    }

    @Test func splitsLikeAShell() {
        #expect(ShellQuoting.split(#"-e "env=staging prod" --tags 'a b' x\ y"#) == [
            "-e", "env=staging prod", "--tags", "a b", "x y",
        ])
        #expect(ShellQuoting.split("   ") == [])
        #expect(ShellQuoting.split(#"-e '' "#) == ["-e", ""])
    }
}

struct SelectionTests {
    @Test func tracksIncludedAndExcluded() {
        var selection = Selection()
        selection.set("web", to: .included)
        selection.set("db", to: .excluded)
        selection.set("cache", to: .included)
        #expect(selection.limitPatterns == ["web", "cache", "!db"])

        selection.set("web", to: .excluded)
        #expect(selection.state(of: "web") == .excluded)
        #expect(selection.limitPatterns == ["cache", "!db", "!web"])

        selection.keep(only: ["web"])
        #expect(selection.limitPatterns == ["!web"])
    }

    @Test func parsesLimitPatterns() {
        let selection = Selection(limitPatterns: ["web", "!db"])
        #expect(selection.included == ["web"])
        #expect(selection.excluded == ["db"])
    }
}
