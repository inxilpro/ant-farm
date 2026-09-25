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
    static let selectionsPrefix = "workspace:"
}

enum AppDefaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.confirmLiveRuns: true,
            SettingsKey.alwaysDiff: true,
            SettingsKey.saveHistory: true,
            SettingsKey.terminalFontSize: 12.0,
        ])
    }

    static var recentDirectories: [String] {
        get { UserDefaults.standard.stringArray(forKey: SettingsKey.recentDirectories) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(10)), forKey: SettingsKey.recentDirectories) }
    }
}

/// What Ant Farm remembers about a workspace between launches.
nonisolated struct SavedSelections: Codable, Sendable {
    var inventoryID: String?
    var playbook: String?
    var limit = Selection()
    var tags = Selection()
    var extraArguments = ""
}
