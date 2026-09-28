//
//  RunNotifier.swift
//  Ant Farm
//

import Foundation
import UserNotifications

/// Tells the user a run finished while they were in another app.
enum RunNotifier {
    nonisolated static let directoryKey = "directory"

    static func post(status: TerminalController.Status, mode: RunMode, workspace: String, directory: URL, recap: [RunReport.HostRecap]) {
        let content = UNMutableNotificationContent()
        content.title = title(for: status, mode: mode)
        content.subtitle = workspace
        content.body = recap.isEmpty ? "" : RunReport.headline(for: recap)
        content.userInfo = [directoryKey: directory.path]
        content.threadIdentifier = directory.path
        if case .finished(let code) = status, code != 0 {
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task {
            let center = UNUserNotificationCenter.current()
            // Asked for on the first background run, when the reason for the prompt is obvious.
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    private static func title(for status: TerminalController.Status, mode: RunMode) -> String {
        let run = mode == .live ? "Live run" : "Check run"
        switch status {
        case .finished(let code) where code == 0: return "\(run) finished"
        case .finished: return "\(run) failed"
        case .stopped: return "\(run) stopped"
        case .idle, .running: return run
        }
    }
}
