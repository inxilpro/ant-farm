//
//  RunPlanTests.swift
//  Ant FarmTests
//

import Foundation
import Testing
@testable import Ant_Farm

struct RunPlanTests {
    /// Output of `ansible-playbook --list-hosts --list-tasks` (ansible-core 2.19).
    static let output = """

    playbook: site.yml

      play #1 (web): Web servers\tTAGS: [webplay]
        pattern: ['web']
        hosts (2):
          web2
          web1
        tasks:
          web : Install nginx\tTAGS: [nginx, webplay]
          include_tasks\tTAGS: [webplay]
          Write file\tTAGS: [deploy, webplay]

      play #2 (db): db\tTAGS: []
        pattern: ['db']
        hosts (0):
        tasks:
    """

    @Test func parsesPlaysHostsAndTasks() {
        let plan = RunPlan.parse(Self.output)
        #expect(plan.plays.count == 2)

        let web = plan.plays[0]
        #expect(web.number == 1)
        #expect(web.name == "Web servers")
        #expect(web.pattern == ["web"])
        #expect(web.tags == ["webplay"])
        #expect(web.hosts == ["web1", "web2"])
        #expect(web.tasks.map(\.name) == ["Install nginx", "include_tasks", "Write file"])
        #expect(web.tasks[0].role == "web")
        #expect(web.tasks[0].tags == ["nginx", "webplay"])
        #expect(web.tasks[1].isDynamicInclude)
        #expect(!web.tasks[2].isDynamicInclude)

        let db = plan.plays[1]
        #expect(db.name == "db")
        #expect(db.hosts.isEmpty)
        #expect(db.tasks.isEmpty)
        #expect(db.tags.isEmpty)

        #expect(plan.hosts == ["web1", "web2"])
        #expect(plan.taskCount == 3)
        #expect(plan.tags == ["deploy", "nginx", "webplay"])
        #expect(plan.hasDynamicIncludes)
    }

    @Test func keepsComplexPatterns() {
        let plan = RunPlan.parse("""
          play #1 (web:&prod): Deploy\tTAGS: []
            pattern: ['web:&prod', 'db']
            hosts (1):
              web1
            tasks:
              Run it\tTAGS: []
        """)
        #expect(plan.plays.first?.pattern == ["web:&prod", "db"])
        #expect(plan.plays.first?.tasks.first?.tags == [])
    }

    @Test func parsesEmptyOutput() {
        #expect(RunPlan.parse("").plays.isEmpty)
        #expect(RunPlan.parse("playbook: site.yml\n").plays.isEmpty)
    }

    @Test func buildsPlanArguments() {
        let command = AnsibleCommand(
            inventory: ["hosts"],
            playbook: "site.yml",
            limit: ["web"],
            tags: ["deploy"],
            mode: .live,
            diff: false,
            extra: ["-K", "-e", "env=prod", "--ask-vault-pass"]
        )
        #expect(Discovery.planArguments(for: command) == [
            "-i", "hosts", "--tags", "deploy", "--limit", "web",
            "-e", "env=prod", "--list-hosts", "--list-tasks", "site.yml",
        ])
    }

    @Test func readsCallbackPluginPaths() {
        let json = """
        [{"name": "DEFAULT_CALLBACK_PLUGIN_PATH", "origin": "/work/ansible.cfg", "value": ["/work/cb", "/x/y"]}]
        """
        #expect(Discovery.parseCallbackPluginPaths(Data(json.utf8)) == ["/work/cb", "/x/y"])
        #expect(Discovery.parseCallbackPluginPaths(Data("[]".utf8)) == AnsibleConfig.defaultCallbackPluginPaths)
    }
}
