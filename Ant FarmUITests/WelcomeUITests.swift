//
//  WelcomeUITests.swift
//  Ant FarmUITests
//

import XCTest

final class WelcomeUITests: AntFarmUITestCase {
    @MainActor
    func testOpensARecentFolder() {
        launch(recents: [fixture.folder])

        XCTAssertTrue(window.buttons["Open Folder…"].waitForExistence(timeout: 10))
        let recent = window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Fixture.folderName + ",")).firstMatch
        XCTAssertTrue(recent.exists)

        recent.click()

        XCTAssertTrue(hostRow("web1").waitForExistence(timeout: 10))
        XCTAssertEqual(window.title, Fixture.folderName)
    }

    @MainActor
    func testWarnsWhenAnsibleIsMissing() {
        launch(recents: [fixture.folder], ansible: fixture.emptyFolder)

        let warning = window.staticTexts["Ansible wasn't found. Install it or set its folder in Settings."]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
    }

    @MainActor
    func testWorkspaceExplainsWhenAnsibleIsMissing() {
        launch(opening: fixture.folder, ansible: fixture.emptyFolder)

        XCTAssertTrue(window.staticTexts["Ansible Not Found"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["Open Settings…"].exists)
        XCTAssertFalse(runButton.isEnabled)
    }
}
