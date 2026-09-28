//
//  AntFarmUITestCase.swift
//  Ant FarmUITests
//

import XCTest

/// Launches Ant Farm against a fresh `Fixture`, with settings of its own.
class AntFarmUITestCase: XCTestCase {
    var fixture: Fixture!
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        fixture = try Fixture()
    }

    override func tearDown() async throws {
        await MainActor.run { app?.terminate() }
        fixture?.remove()
    }

    /// Launches the app, showing `folder` as if it were open when the app last quit, or else
    /// the welcome screen. With neither a folder nor `recents`, the app shows the open panel
    /// as it does on first launch.
    @MainActor
    func launch(opening folder: URL? = nil, recents: [URL] = [], ansible: URL? = nil, environment: [String: String] = [:]) {
        let app = XCUIApplication()
        app.launchEnvironment["ANTFARM_UI_TESTING"] = "1"
        app.launchEnvironment.merge(environment) { $1 }
        // Settings given as arguments go in the argument domain, ahead of the app's own store.
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-ansibleDirectory", (ansible ?? Fixture.fakeAnsible).path,
            "-recentDirectories", plistArray(recents.map(\.path)),
        ]
        if let folder {
            app.launchArguments += ["-lastDirectory", folder.path]
        }
        app.launch()
        self.app = app
    }

    @MainActor
    func launchWorkspace(environment: [String: String] = [:]) {
        launch(opening: fixture.folder, environment: environment)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(hostRow("web1").waitForExistence(timeout: 10), "The fixture's hosts never loaded")
    }

    private func plistArray(_ strings: [String]) -> String {
        "(" + strings.map { "\"\($0)\"" }.joined(separator: ",") + ")"
    }

    // MARK: Elements

    @MainActor var window: XCUIElement { app.windows.firstMatch }

    @MainActor var hostList: XCUIElement { window.outlines["Sidebar"] }

    @MainActor var tagList: XCUIElement { window.outlines.element(boundBy: 1) }

    /// A host's row in the sidebar. A group's row is labeled with its name and host count, e.g. "web, 2".
    @MainActor func hostRow(_ name: String) -> XCUIElement {
        hostList.buttons[name]
    }

    @MainActor func tagRow(_ name: String) -> XCUIElement {
        tagList.buttons[name]
    }

    /// The command the run pane shows.
    @MainActor var command: XCUIElement {
        // Selectable text is reported as a text inside a text, and only the inner one's value keeps up.
        window.staticTexts["command"].staticTexts.firstMatch
    }

    @MainActor var runButton: XCUIElement { window.toolbars.buttons["Run"] }

    // MARK: Waiting

    /// Waits for `element`'s value to become `value`.
    @MainActor
    func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: element)
        if XCTWaiter.wait(for: [found], timeout: timeout) != .completed {
            XCTFail("Expected value \"\(value)\", got \"\(element.value ?? "nil")\"", file: file, line: line)
        }
    }

    /// Waits for the command to contain (or, with `false`, lose) `text`.
    @MainActor
    func waitForCommand(containing text: String, _ contains: Bool = true, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let format = contains ? "value CONTAINS %@" : "NOT (value CONTAINS %@)"
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, text), object: command)
        if XCTWaiter.wait(for: [found], timeout: timeout) != .completed {
            XCTFail("Expected the command \(contains ? "to" : "not to") contain \"\(text)\", got \"\(command.value ?? "nil")\"", file: file, line: line)
        }
    }

    /// Waits for `element` to go away.
    @MainActor
    func waitForNonexistence(of element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForNonExistence(timeout: timeout) {
            XCTFail("\(element) is still there", file: file, line: line)
        }
    }
}
