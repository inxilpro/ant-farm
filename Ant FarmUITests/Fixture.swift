//
//  Fixture.swift
//  Ant FarmUITests
//

import Foundation

/// A throwaway Ansible project for Ant Farm to open.
///
/// The project is run with the fake Ansible in `FakeAnsible/`, so the UI tests don't need
/// Ansible installed and always see the same hosts, tags, plan, and run.
struct Fixture {
    static let folderName = "infrastructure"

    /// The fake Ansible's folder, inside the test bundle.
    ///
    /// The test runner is sandboxed, so scripts it writes itself are quarantined and won't run.
    static let fakeAnsible: URL = {
        guard let script = Bundle(for: AntFarmUITestCase.self).url(forResource: "ansible-playbook", withExtension: nil) else {
            fatalError("FakeAnsible/ansible-playbook is missing from the test bundle")
        }
        return script.deletingLastPathComponent()
    }()

    let root: URL
    /// The folder Ant Farm opens.
    let folder: URL
    /// An empty folder, for a Mac without Ansible.
    let emptyFolder: URL

    var historyFile: URL { folder.appending(path: ".ansible-interactive-history") }

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appending(path: "AntFarmUITests-\(UUID().uuidString)")
        folder = root.appending(path: Self.folderName)
        emptyFolder = root.appending(path: "empty")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        try Self.inventory.write(to: folder.appending(path: "hosts"), atomically: true, encoding: .utf8)
        try Self.sitePlaybook.write(to: folder.appending(path: "site.yml"), atomically: true, encoding: .utf8)
        try Self.deployPlaybook.write(to: folder.appending(path: "deploy.yml"), atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The commands saved to the workspace's history file, newest first.
    func history() -> [[String]] {
        guard let data = try? Data(contentsOf: historyFile) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String]]) ?? []
    }

    // The fake Ansible doesn't read these, but Ant Farm's own discovery does.

    static let inventory = """
    [web]
    web1
    web2

    [db]
    db1

    """

    static let sitePlaybook = """
    - name: Web servers
      hosts: web
      tasks:
        - name: Install nginx
          ansible.builtin.debug: { msg: nginx }
          tags: [nginx, setup]
        - name: Deploy app
          ansible.builtin.debug: { msg: deploy }
          tags: [deploy]

    """

    static let deployPlaybook = """
    - name: Deploy
      hosts: all
      tasks:
        - name: Deploy app
          ansible.builtin.debug: { msg: deploy }

    """
}
