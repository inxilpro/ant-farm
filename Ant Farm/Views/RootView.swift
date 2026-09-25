//
//  RootView.swift
//  Ant Farm
//

import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var started = false

    var body: some View {
        Group {
            if let workspace = app.workspace {
                WorkspaceView(workspace: workspace)
                    .id(workspace.directory)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .task {
            // Unit tests are hosted in the app; a modal open panel would stall them.
            guard !started, !AppDefaults.isRunningTests else { return }
            started = true
            let opened = await app.start()
            // First launch: go straight to the folder picker.
            if !opened && app.recentDirectories.isEmpty {
                app.chooseDirectory()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .antFarmRunFinished)) { _ in
            if !NSApp.isActive {
                NSApp.requestUserAttention(.informationalRequest)
            }
        }
    }
}
