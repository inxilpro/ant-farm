//
//  CommandErrorView.swift
//  Ant Farm
//

import SwiftUI

/// Shows why a helper command failed, with an explanation in place of the raw
/// output when the cause is one Ant Farm recognizes.
struct CommandErrorView: View {
    @Environment(\.openURL) private var openURL

    let title: String
    let error: String
    var monospaced = false
    let retry: () -> Void

    // Files & Folders is where macOS lists the "Data shared by…" app data permissions.
    private static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    var body: some View {
        switch CommandFailure.recognize(error) {
        case .onePasswordAccess:
            ContentUnavailableView {
                Label(title, systemImage: "lock.trianglebadge.exclamationmark")
            } description: {
                Text("Your vault password script uses the 1Password CLI, which can’t reach 1Password from Ant Farm. In Privacy & Security, under Files & Folders, turn on the 1Password data for Ant Farm, then try again.")
                    .help(error)
            } actions: {
                Button("Open Privacy Settings") { openURL(Self.privacySettings) }
                Button("Try Again", action: retry)
            }
        case nil:
            ContentUnavailableView {
                Label(title, systemImage: "exclamationmark.triangle")
            } description: {
                if monospaced {
                    ScrollView {
                        Text(error)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 240)
                } else {
                    Text(error).textSelection(.enabled)
                }
            } actions: {
                Button("Try Again", action: retry)
            }
        }
    }
}
