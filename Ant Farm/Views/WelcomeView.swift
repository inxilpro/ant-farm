//
//  WelcomeView.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// Shown when no workspace is open.
struct WelcomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("Ant Farm")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose a folder that contains your Ansible inventory and playbooks.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                app.chooseDirectory()
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !app.recentDirectories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(app.recentDirectories.prefix(5), id: \.self) { url in
                        Button {
                            Task { await app.open(url) }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                    Text(url.deletingLastPathComponent().path.abbreviatingHome)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill").foregroundStyle(.tint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(url.path.abbreviatingHome)
                        .contextMenu {
                            Button("Open") { Task { await app.open(url) } }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            Divider()
                            Button("Remove from Recents") { app.removeRecent(url) }
                        }
                    }
                }
                .frame(width: 320)
            }

            if app.tools == nil && !app.isLocatingTools {
                Label("Ansible wasn't found. Install it or set its folder in Settings.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFolder) else { return false }
            Task { await app.open(url) }
            return true
        }
    }
}
