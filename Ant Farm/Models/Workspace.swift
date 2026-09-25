//
//  Workspace.swift
//  Ant Farm
//

import Foundation
import Observation

/// One folder of Ansible content: its inventories, playbooks, tags, and the current selections.
@Observable
final class Workspace {
    let directory: URL
    var tools: AnsibleTools?

    var name: String { directory.lastPathComponent }

    // Discovery
    private(set) var inventories: [InventorySource] = []
    private(set) var playbooks: [Playbook] = []
    private(set) var isDiscovering = false

    var selectedInventoryID: String? {
        didSet {
            guard selectedInventoryID != oldValue else { return }
            save()
            if !suppressLoads {
                Task {
                    await loadInventoryContents()
                    await loadTags()
                }
            }
        }
    }

    var selectedPlaybookPath: String? {
        didSet {
            guard selectedPlaybookPath != oldValue else { return }
            save()
            if !suppressLoads { Task { await loadTags() } }
        }
    }

    // Inventory contents
    private(set) var contents: InventoryContents = .empty
    private(set) var isLoadingInventory = false
    private(set) var inventoryError: String?

    // Tags
    private(set) var tags: [String] = []
    private(set) var isLoadingTags = false
    private(set) var tagsError: String?

    // Selections
    var limit = Selection() { didSet { save() } }
    var tagSelection = Selection() { didSet { save() } }
    var extraArguments = "" { didSet { save() } }
    var mode: RunMode = .check

    private(set) var history: [[String]] = []

    private var restoring = false
    private var suppressLoads = false

    var selectedInventory: InventorySource? {
        inventories.first { $0.id == selectedInventoryID }
    }

    var selectedPlaybook: Playbook? {
        playbooks.first { $0.path == selectedPlaybookPath }
    }

    init(directory: URL, tools: AnsibleTools?) {
        self.directory = directory.standardizedFileURL
        self.tools = tools
    }

    // MARK: Loading

    func reload() async {
        isDiscovering = true
        defer { isDiscovering = false }

        let directory = directory
        async let found = Discovery.inventories(in: directory)
        async let foundPlaybooks = Discovery.playbooks(in: directory)
        var configured: InventorySource?
        if let tools {
            configured = await Discovery.configuredInventory(in: directory, tools: tools)
        }

        var sources = await found
        if let configured {
            sources.insert(configured, at: 0)
        } else if sources.isEmpty {
            // Nothing found on disk; let Ansible fall back to its own default.
            sources = [InventorySource(paths: [], label: "Ansible default", hint: "/etc/ansible/hosts")]
        }
        inventories = sources
        playbooks = await foundPlaybooks
        history = RunHistory.load(from: directory)

        restore()
        await loadInventoryContents()
        await loadTags()
    }

    func loadInventoryContents() async {
        guard let source = selectedInventory, let tools else {
            contents = .empty
            inventoryError = tools == nil ? nil : "Choose an inventory."
            return
        }
        isLoadingInventory = true
        inventoryError = nil
        defer { isLoadingInventory = false }
        do {
            let loaded = try await Discovery.contents(of: source, in: directory, tools: tools)
            guard source.id == selectedInventoryID else { return }
            contents = loaded
            limit.keep(only: Set(loaded.hosts + loaded.groups.map(\.name)))
        } catch {
            guard source.id == selectedInventoryID else { return }
            contents = .empty
            inventoryError = error.localizedDescription
        }
    }

    func loadTags() async {
        guard let playbook = selectedPlaybook, let tools else {
            tags = []
            tagsError = nil
            return
        }
        isLoadingTags = true
        tagsError = nil
        defer { isLoadingTags = false }
        do {
            let loaded = try await Discovery.tags(for: playbook, inventory: selectedInventory, in: directory, tools: tools)
            guard playbook.path == selectedPlaybookPath else { return }
            tags = loaded
            tagSelection.keep(only: Set(loaded))
        } catch {
            guard playbook.path == selectedPlaybookPath else { return }
            tags = []
            tagsError = error.localizedDescription
        }
    }

    // MARK: Commands

    var extraArgumentList: [String] {
        ShellQuoting.split(extraArguments)
    }

    /// The command the current selections describe, or nil until a playbook is chosen.
    func command(mode: RunMode? = nil, diff: Bool = true) -> AnsibleCommand? {
        guard let playbook = selectedPlaybook else { return nil }
        return AnsibleCommand(
            inventory: selectedInventory?.paths ?? [],
            playbook: playbook.path,
            limit: limit.limitPatterns,
            tags: tagSelection.included,
            skipTags: tagSelection.excluded,
            mode: mode ?? self.mode,
            diff: diff,
            extra: extraArgumentList
        )
    }

    func recordRun(_ argv: [String]) {
        if let saved = try? RunHistory.save(argv, in: directory) {
            history = saved
        } else {
            history = [argv] + history.filter { $0 != argv }
        }
    }

    /// Restores the selections a past command used, as far as they still apply.
    func apply(_ command: AnsibleCommand) {
        restoring = true
        defer {
            restoring = false
            save()
        }
        if let source = inventories.first(where: { $0.paths == command.inventory }) {
            selectedInventoryID = source.id
        }
        if playbooks.contains(where: { $0.path == command.playbook }) {
            selectedPlaybookPath = command.playbook
        }
        limit = Selection(limitPatterns: command.limit)
        tagSelection = Selection(included: command.tags, excluded: command.skipTags)
        extraArguments = ShellQuoting.format(command.extra)
        mode = command.mode
    }

    // MARK: Persistence

    private var defaultsKey: String { SettingsKey.selectionsPrefix + directory.path }

    private func restore() {
        restoring = true
        suppressLoads = true
        defer {
            restoring = false
            suppressLoads = false
        }

        var saved = SavedSelections()
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(SavedSelections.self, from: data) {
            saved = decoded
        }

        selectedInventoryID = inventories.first { $0.id == saved.inventoryID }?.id ?? inventories.first?.id
        selectedPlaybookPath = playbooks.first { $0.path == saved.playbook }?.path ?? playbooks.first?.path
        limit = saved.limit
        tagSelection = saved.tags
        extraArguments = saved.extraArguments
    }

    private func save() {
        guard !restoring else { return }
        let saved = SavedSelections(
            inventoryID: selectedInventoryID,
            playbook: selectedPlaybookPath,
            limit: limit,
            tags: tagSelection,
            extraArguments: extraArguments
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
