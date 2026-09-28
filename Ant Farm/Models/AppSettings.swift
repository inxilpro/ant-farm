//
//  AppSettings.swift
//  Ant Farm
//

import Foundation

/// UserDefaults keys, shared by `@AppStorage` in views and the models.
enum SettingsKey {
    static let lastDirectory = "lastDirectory"
    static let recentDirectories = "recentDirectories"
    static let ansibleDirectory = "ansibleDirectory"
    static let confirmLiveRuns = "confirmLiveRuns"
    static let alwaysDiff = "alwaysDiff"
    static let saveHistory = "saveHistory"
    static let terminalFontSize = "terminalFontSize"
    static let runView = "runView"
    static let onlyChanges = "onlyChanges"
    static let tagsPaneWidth = "tagsPaneWidth"
    static let selectionsPrefix = "workspace:"
}

enum AppDefaults {
    /// Where Ant Farm keeps its settings. UI tests get a store of their own, emptied at
    /// launch unless a test is relaunching, so they start from a known state and leave the
    /// user's settings alone.
    nonisolated static let store: UserDefaults = {
        guard isUITesting, let store = UserDefaults(suiteName: uiTestingSuite) else { return .standard }
        if ProcessInfo.processInfo.environment["ANTFARM_UI_TESTING_KEEP_SETTINGS"] != "1" {
            store.removePersistentDomain(forName: uiTestingSuite)
        }
        return store
    }()

    private nonisolated static let uiTestingSuite = "com.cmorrell.Ant-Farm.UITesting"

    static func register() {
        store.register(defaults: [
            SettingsKey.confirmLiveRuns: true,
            SettingsKey.alwaysDiff: true,
            SettingsKey.saveHistory: true,
            SettingsKey.terminalFontSize: 12.0,
        ])
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set by the UI tests when they launch the app.
    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.environment["ANTFARM_UI_TESTING"] == "1"
    }

    static var recentDirectories: [String] {
        get { store.stringArray(forKey: SettingsKey.recentDirectories) ?? [] }
        set { store.set(Array(newValue.prefix(10)), forKey: SettingsKey.recentDirectories) }
    }
}

/// How the detail pane shows a run: Ant Farm's report, or Ansible's own terminal output.
enum RunView: String {
    case summary
    case terminal
}

/// What Ant Farm remembers about a workspace between launches.
nonisolated struct SavedSelections: Codable, Sendable {
    var inventoryID: String?
    var playbook: String?
    var limit = Selection()
    var tags = Selection()
    var extraArguments = ""
}
