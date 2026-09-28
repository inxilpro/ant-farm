//
//  RootView.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// One window: the welcome screen until it has a folder, then that folder's workspace.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    /// The folder this window presents. SwiftUI saves it for state restoration.
    @Binding var directory: URL?
    @State private var session = WindowSession()

    var body: some View {
        Group {
            if let workspace = session.workspace {
                WorkspaceView(workspace: workspace)
                    .id(workspace.directory)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .environment(session)
        .focusedSceneValue(session)
        .background(WindowReader { window in
            if let window { session.window = window }
        })
        // A window with a run in progress can't close; Stop it first.
        .windowDismissBehavior(session.terminal.isRunning ? .disabled : .automatic)
        .onAppear {
            app.register(session)
            let openWindow = openWindow
            app.openWindow = { openWindow(value: $0) }
            session.presentFolder = { directory = $0 }
        }
        // An open window takes folders from Finder and the Dock, so SwiftUI doesn't add an
        // empty window for each one; AppState then picks the window that should show it.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in
            app.openFromSystem(url)
        }
        .task(id: directory) {
            await session.load(directory)
        }
        .task {
            // Unit tests are hosted in the app; a modal open panel would stall them.
            guard !AppDefaults.isRunningTests else { return }
            await app.start()
            guard directory == nil else { return }
            if let url = app.folderToRestore() {
                directory = url
            } else if app.recentDirectories.isEmpty && app.sessions.count == 1 {
                // First launch: go straight to the folder picker.
                app.chooseDirectory(for: session)
            }
        }
    }
}

/// Reports the window a view is in.
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onChange: onChange)
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        let onChange: (NSWindow?) -> Void

        init(onChange: @escaping (NSWindow?) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange(window)
        }
    }
}
