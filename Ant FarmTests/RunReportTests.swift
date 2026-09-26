//
//  RunReportTests.swift
//  Ant FarmTests
//

import Foundation
import Testing
@testable import Ant_Farm

struct RunReportTests {
    /// Events written by Callback/antfarm.py for a small check run.
    static let events = """
    {"playbook": "site.yml", "event": "playbook_start", "time": 1.0}
    {"play": "p1", "name": "Web servers", "pattern": "web", "event": "play_start", "time": 1.1}
    {"handler": false, "prompts": false, "task": "t1", "name": "web : Install nginx", "action": "debug", "role": "web", "event": "task_start", "time": 1.2}
    {"host": "web1", "task": "t1", "event": "host_start", "time": 1.3}
    {"host": "web2", "task": "t1", "event": "host_start", "time": 1.3}
    {"host": "web1", "task": "t1", "changed": false, "msg": "installing", "event": "ok", "time": 1.4}
    {"host": "web2", "task": "t1", "changed": true, "diff": "--- before\\n+++ after\\n@@ -0,0 +1 @@\\n+hello\\n", "event": "ok", "time": 1.4}
    {"handler": false, "prompts": false, "task": "t2", "name": "Fail", "action": "command", "role": null, "event": "task_start", "time": 1.5}
    {"host": "web1", "task": "t2", "event": "host_start", "time": 1.5}
    {"host": "web2", "task": "t2", "event": "host_start", "time": 1.5}
    {"host": "web1", "task": "t2", "changed": false, "skipReason": "Conditional result was False", "event": "skipped", "time": 1.6}
    {"host": "web2", "task": "t2", "changed": true, "msg": "non-zero return code", "rc": 1, "stderr": "boom", "event": "failed", "time": 1.7}
    """

    static func report(_ lines: String) -> RunReport {
        var report = RunReport()
        for line in lines.split(separator: "\n") {
            if let event = RunEvent.parse(line) {
                report.apply(event)
            }
        }
        return report
    }

    @Test func buildsPlaysAndTasks() throws {
        let report = Self.report(Self.events)
        #expect(report.playbook == "site.yml")
        #expect(report.plays.count == 1)

        let play = try #require(report.plays.first)
        #expect(play.name == "Web servers")
        #expect(play.tasks.map(\.id) == ["t1", "t2"])

        let install = play.tasks[0]
        #expect(install.role == "web")
        #expect(install.status == .changed)
        #expect(install.count(.ok) == 1)
        #expect(install.count(.changed) == 1)
        #expect(install.hasDiff)
        #expect(install.results.map(\.host) == ["web1", "web2"])

        let fail = play.tasks[1]
        #expect(fail.status == .failed)
        #expect(fail.needsAttention)
        #expect(fail.results[1].rc == 1)
        #expect(fail.results[1].stderr == "boom")
        #expect(fail.results[0].skipReason == "Conditional result was False")
    }

    @Test func countsProgressUntilTheRecapArrives() throws {
        var report = Self.report(Self.events)
        let web2 = try #require(report.recap.first { $0.host == "web2" })
        #expect(web2.stats.ok == 1)
        #expect(web2.stats.changed == 1)
        #expect(web2.stats.failed == 1)
        #expect(web2.status == .failed)

        report.apply(try #require(RunEvent.parse("""
        {"hosts": {"web1": {"ok": 1, "changed": 0, "failed": 0, "unreachable": 0, "skipped": 1, "rescued": 0, "ignored": 0}}, "event": "stats"}
        """)))
        #expect(report.recap.map(\.host) == ["web1"])
        #expect(report.recap.first?.stats.skipped == 1)
    }

    @Test func showsRunningHostsUntilTheyFinish() {
        var report = Self.report("""
        {"event": "play_start", "play": "p1", "name": "all", "pattern": "all"}
        {"event": "task_start", "task": "t1", "name": "Slow"}
        {"event": "host_start", "task": "t1", "host": "web1"}
        """)
        #expect(report.currentTask?.status == .running)
        report.finish()
        #expect(report.currentTask?.results.isEmpty == true)
    }

    @Test func tracksPrompts() {
        var report = Self.report("""
        {"event": "playbook_start", "playbook": "site.yml"}
        {"event": "vars_prompt", "name": "who"}
        """)
        #expect(report.isWaitingForInput)

        report.apply(RunEvent(event: "play_start", play: "p1", name: "all", pattern: "all"))
        #expect(!report.isWaitingForInput)

        report.apply(RunEvent(event: "task_start", name: "Wait", task: "t1", action: "pause", prompts: true))
        report.apply(RunEvent(event: "host_start", task: "t1", host: "web1"))
        #expect(report.isWaitingForInput)

        report.apply(RunEvent(event: "ok", task: "t1", host: "web1"))
        #expect(!report.isWaitingForInput)
    }

    @Test func keepsOneRowWhenATaskStartsAgain() {
        let report = Self.report("""
        {"event": "play_start", "play": "p1", "name": "all", "pattern": "all"}
        {"event": "task_start", "task": "t1", "name": "Included"}
        {"event": "ok", "task": "t1", "host": "web1"}
        {"event": "task_start", "task": "t1", "name": "Included"}
        {"event": "ok", "task": "t1", "host": "web2"}
        """)
        #expect(report.tasks.count == 1)
        #expect(report.tasks.first?.results.map(\.host) == ["web1", "web2"])
    }

    /// The tests run inside the app, so this checks the plugin ships as a resource.
    @Test func bundlesTheCallbackPlugin() throws {
        let url = try #require(Bundle.main.url(forResource: "antfarm", withExtension: "py"))
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("ANTFARM_EVENTS"))
    }

    @Test func ignoresBadLines() {
        #expect(RunEvent.parse("not json") == nil)
        #expect(RunEvent.parse("{}") == nil)
    }
}
