//
//  DiscoveryTests.swift
//  Ant FarmTests
//

import Foundation
import Testing
@testable import Ant_Farm

struct DiscoveryTests {
    @Test func parsesListTags() {
        let output = """
        playbook: site.yml

          play #1 (all): all\tTAGS: [setup]
              TASK TAGS: [deploy, nginx, setup]

          play #2 (db): db\tTAGS: []
              TASK TAGS: [postgres]
        """
        #expect(Discovery.parseListTags(output) == ["deploy", "nginx", "postgres", "setup"])
    }

    @Test func recognizesIniInventories() {
        #expect(Discovery.looksLikeIniInventory(name: "production", contents: "[web]\nweb1\n"))
        #expect(Discovery.looksLikeIniInventory(name: "hosts", contents: "web1\nweb2\n"))
        #expect(!Discovery.looksLikeIniInventory(name: "notes", contents: "web1\n"))
        #expect(!Discovery.looksLikeIniInventory(name: "binary", contents: "[web]\0"))
    }

    @Test func recognizesYamlInventories() {
        #expect(Discovery.looksLikeYamlInventory("""
        all:
          children:
            web:
              hosts:
                web1:
        """))
        #expect(Discovery.looksLikeYamlInventory("plugin: amazon.aws.aws_ec2\nregions: [us-east-1]\n"))
        #expect(!Discovery.looksLikeYamlInventory("- hosts: all\n  tasks: []\n"))
        #expect(!Discovery.looksLikeYamlInventory("name: something\nversion: 2\n"))
    }

    @Test func recognizesPlaybooks() {
        let playbook = Discovery.parsePlaybook(path: "site.yml", contents: """
        - name: Configure web servers
          hosts: web
          tasks: []
        - import_playbook: db.yml
        """)
        #expect(playbook == Playbook(path: "site.yml", name: "Configure web servers"))

        #expect(Discovery.parsePlaybook(path: "vars.yml", contents: "key: value\n") == nil)
        #expect(Discovery.parsePlaybook(path: "tasks.yml", contents: "- name: task\n  debug: {}\n") == nil)
        #expect(Discovery.parsePlaybook(path: "empty.yml", contents: "") == nil)
    }

    @Test func parsesConfigDump() throws {
        let json = """
        [{"name": "DEFAULT_HOST_LIST", "origin": "/work/ansible.cfg", "value": ["/work/inventory/hosts"]}]
        """
        let source = try #require(Discovery.parseConfigDump(Data(json.utf8), relativeTo: URL(fileURLWithPath: "/work")))
        #expect(source.isDefault)
        #expect(source.label == "inventory/hosts")
        #expect(source.hint == "Default from ansible.cfg")
    }

    @Test func findsInventoriesAndPlaybooksOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appending(path: "inventories/prod"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "playbooks"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "[web]\nweb1\n".write(to: dir.appending(path: "hosts.ini"), atomically: true, encoding: .utf8)
        try "[db]\ndb1\n".write(to: dir.appending(path: "inventories/staging"), atomically: true, encoding: .utf8)
        try "- hosts: all\n  tasks: []\n".write(to: dir.appending(path: "site.yml"), atomically: true, encoding: .utf8)
        try "- hosts: web\n  tasks: []\n".write(to: dir.appending(path: "playbooks/web.yaml"), atomically: true, encoding: .utf8)
        try "key: value\n".write(to: dir.appending(path: "vars.yml"), atomically: true, encoding: .utf8)

        let inventories = await Discovery.inventories(in: dir)
        #expect(inventories.map(\.label) == ["hosts.ini", "inventories/prod", "inventories/staging"])

        let playbooks = await Discovery.playbooks(in: dir)
        #expect(playbooks.map(\.path) == ["site.yml", "playbooks/web.yaml"])
    }
}

struct InventoryContentsTests {
    @Test func resolvesNestedGroups() throws {
        let json = """
        {
          "_meta": {"hostvars": {"web1": {}, "web2": {}, "db1": {}, "lonely": {}}},
          "all": {"children": ["ungrouped", "prod"]},
          "prod": {"children": ["web", "db"]},
          "web": {"hosts": ["web1", "web2"]},
          "db": {"hosts": ["db1"]},
          "empty": {"hosts": []},
          "ungrouped": {"hosts": ["lonely"]}
        }
        """
        let contents = try InventoryContents.parse(Data(json.utf8))
        #expect(contents.groups.map(\.name) == ["db", "prod", "ungrouped", "web"])
        #expect(contents.groups.first { $0.name == "prod" }?.hosts == ["db1", "web1", "web2"])
        #expect(contents.hosts == ["db1", "lonely", "web1", "web2"])
    }
}

struct RunHistoryTests {
    @Test func migratesOldQuotedArguments() {
        let data = Data(#"[["ansible-playbook", "--tags='a,b'", "site.yml"], "junk", []]"#.utf8)
        #expect(RunHistory.parse(data) == [["ansible-playbook", "--tags=a,b", "site.yml"]])
    }

    @Test func savesNewestFirstWithoutDuplicates() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try RunHistory.save(["ansible-playbook", "a.yml"], in: dir)
        try RunHistory.save(["ansible-playbook", "b.yml"], in: dir)
        try RunHistory.save(["ansible-playbook", "a.yml"], in: dir)
        #expect(RunHistory.load(from: dir) == [["ansible-playbook", "a.yml"], ["ansible-playbook", "b.yml"]])
    }
}

struct LoginShellTests {
    @Test func parsesEnvironmentAfterMarker() {
        let output = "motd noise\n__ANT_FARM_ENV__PATH=/opt/homebrew/bin:/usr/bin\0HOME=/Users/me\0EQ=a=b\0"
        let env = LoginShell.parse(Data(output.utf8))
        #expect(env?["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(env?["EQ"] == "a=b")
        #expect(LoginShell.parse(Data("no marker".utf8)) == nil)
    }
}
