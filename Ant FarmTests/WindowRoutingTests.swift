//
//  WindowRoutingTests.swift
//  Ant FarmTests
//

import Foundation
import Testing
@testable import Ant_Farm

@MainActor
struct WindowRoutingTests {
    private let folder = URL(fileURLWithPath: "/tmp/ant-farm-tests/site").folderURL
    private let other = URL(fileURLWithPath: "/tmp/ant-farm-tests/other").folderURL

    private func makeApp() -> (AppState, opened: () -> [URL]) {
        let app = AppState()
        var opened: [URL] = []
        app.openWindow = { opened.append($0) }
        return (app, { opened })
    }

    private func window(in app: AppState, showing directory: URL? = nil) -> WindowSession {
        let session = WindowSession()
        app.register(session)
        if let directory {
            session.show(directory)
        }
        return session
    }

    @Test func reusesTheWindowThatAlreadyShowsTheFolder() {
        let (app, opened) = makeApp()
        _ = window(in: app, showing: folder)
        let empty = window(in: app)

        app.open(URL(fileURLWithPath: "/tmp/ant-farm-tests/../ant-farm-tests/site"))

        #expect(opened().isEmpty)
        #expect(empty.directory == nil)
    }

    @Test func fillsAnEmptyWindowBeforeOpeningANewOne() {
        let (app, opened) = makeApp()
        _ = window(in: app, showing: other)
        let empty = window(in: app)

        app.open(folder)

        #expect(opened().isEmpty)
        #expect(empty.directory == folder)
    }

    @Test func prefersTheEmptyWindowThatAsked() {
        let (app, _) = makeApp()
        let first = window(in: app)
        let requester = window(in: app)

        app.open(folder, preferring: requester)

        #expect(requester.directory == folder)
        #expect(first.directory == nil)
    }

    @Test func opensANewWindowWhenEveryWindowHasAFolder() {
        let (app, opened) = makeApp()
        let requester = window(in: app, showing: other)

        app.open(folder, preferring: requester)

        #expect(opened() == [folder])
        #expect(requester.directory == other)
    }
}
