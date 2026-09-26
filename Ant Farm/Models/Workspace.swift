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
                schedulePlan()
            }
        }
    }

    var selectedPlaybookPath: String? {
        didSet {
            guard selectedPlaybookPath != oldValue else { return }
            save()
            if !suppressLoads {
                Task { await loadTags() }
                schedulePlan()
            }
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

    // Plan
    private(set) var plan: RunPlan?
    private(set) var isLoadingPlan = false
    private(set) var planError: String?
    @ObservationIgnored private var planTask: Task<Void, Never>?

    /// Callback plugin folders from ansible.cfg, kept when Ant Farm adds its own.
    private(set) var callbackPluginPaths = AnsibleConfig.defaultCallbackPluginPaths

    // Selections
    var limit = Selection() { didSet { selectionChanged(limit != oldValue) } }
    var tagSelection = Selection() { didSet { selectionChanged(tagSelection != oldValue) } }
    var extraArguments = "" { didSet { selectionChanged(extraArguments != oldValue) } }
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
        var config = AnsibleConfig()
        if let tools {
            config = await Discovery.config(in: directory, tools: tools)
        }
        callbackPluginPaths = config.callbackPluginPaths
        let configured = config.inventory

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
        schedulePlan()
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

    // MARK: Plan

    private func selectionChanged(_ changed: Bool) {
        save()
        if changed && !suppressLoads {
            schedulePlan()
        }
    }

    /// Reloads the plan shortly after the selections stop changing.
    func schedulePlan() {
        planTask?.cancel()
        guard let command = command(), let tools else {
            planTask = nil
            plan = nil
            planError = nil
            isLoadingPlan = false
            return
        }

        isLoadingPlan = true
        let directory = directory
        planTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result: Result<RunPlan, Error>
            do {
                result = .success(try await Discovery.plan(for: command, in: directory, tools: tools))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let plan):
                self.plan = plan
                self.planError = nil
            case .failure(let error):
                self.plan = nil
                self.planError = error.localizedDescription
            }
            self.isLoadingPlan = false
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

    // MARK: Undo

    /// Changes the host and tag selections so Edit > Undo can put them back.
    func changeSelections(_ actionName: String, undoManager: UndoManager?, _ change: (Workspace) -> Void) {
        let before = (limit, tagSelection)
        change(self)
        guard before != (limit, tagSelection) else { return }
        registerUndo(restoring: before, actionName: actionName, undoManager: undoManager)
    }

    private func registerUndo(restoring selections: (Selection, Selection), actionName: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        let current = (limit, tagSelection)
        undoManager.registerUndo(withTarget: self) { workspace in
            MainActor.assumeIsolated {
                workspace.limit = selections.0
                workspace.tagSelection = selections.1
                // Registering the reverse from inside an undo makes it the redo.
                workspace.registerUndo(restoring: current, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
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
