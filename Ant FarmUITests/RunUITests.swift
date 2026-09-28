//
//  RunUITests.swift
//  Ant FarmUITests
//

import XCTest

/// Running the playbook with the fake Ansible, and the report it produces.
final class RunUITests: AntFarmUITestCase {
    @MainActor
    func testCheckRunShowsItsReport() {
        launchWorkspace()
        hostRow("web1").click()
        waitForCommand(containing: "--limit web1")

        runButton.click()

        XCTAssertTrue(window.checkBoxes["Only changes and failures"].waitForExistence(timeout: 10), "The run report never appeared")
        XCTAssertTrue(window.staticTexts["Install nginx"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Deploy app"].exists)
        XCTAssertTrue(runButton.waitForExistence(timeout: 10), "The run never finished")

        XCTAssertEqual(fixture.history().first, ["ansible-playbook", "-i", "hosts", "--check", "--diff", "--limit", "web1", "deploy.yml"])
    }

    @MainActor
    func testClearingARunShowsThePlanAgain() {
        launchWorkspace()

        // Run > Run
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(window.checkBoxes["Only changes and failures"].waitForExistence(timeout: 10))
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))

        // Run > Clear Run
        app.typeKey("k", modifierFlags: .command)

        waitForNonexistence(of: window.checkBoxes["Only changes and failures"])
        XCTAssertTrue(window.staticTexts["Web servers"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStoppingARun() {
        launchWorkspace(environment: ["ANTFARM_FAKE_RUN_SECONDS": "60"])

        runButton.click()

        let stop = window.toolbars.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["Deploy app"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuBars.menuItems["Run in Check Mode"].isEnabled)

        stop.click()

        XCTAssertTrue(runButton.waitForExistence(timeout: 10), "The run didn't stop")
        XCTAssertTrue(app.menuBars.menuItems["Run in Check Mode"].isEnabled)
    }

    @MainActor
    func testLiveRunsAskFirst() {
        launchWorkspace()
        window.toolbars.radioButtons["Live"].click()
        waitForCommand(containing: "--check", false)

        runButton.click()
        // The Touch Bar shows the same buttons, so look for them in the window.
        let cancel = window.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(window.sheets.buttons["Run Live"].exists)
        XCTAssertTrue(window.sheets.buttons["Run in Check Mode"].exists)
        cancel.click()

        waitForNonexistence(of: window.sheets.buttons["Run Live"])
        XCTAssertTrue(fixture.history().isEmpty, "Cancelling still ran the playbook")

        runButton.click()
        window.sheets.buttons["Run Live"].click()

        XCTAssertTrue(window.checkBoxes["Only changes and failures"].waitForExistence(timeout: 10))
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))
        XCTAssertEqual(fixture.history().first, ["ansible-playbook", "-i", "hosts", "--diff", "deploy.yml"])
    }

    @MainActor
    func testRunningAgainFromHistory() {
        launchWorkspace()
        tagRow("nginx").click()
        waitForCommand(containing: "--tags nginx")
        runButton.click()
        XCTAssertTrue(window.checkBoxes["Only changes and failures"].waitForExistence(timeout: 10))
        XCTAssertTrue(runButton.waitForExistence(timeout: 10))
        app.typeKey("k", modifierFlags: .command)

        tagRow("nginx").click()
        waitForCommand(containing: "--tags", false)

        window.toolbars.menuButtons["History"].click()
        app.menuItems["deploy.yml tags nginx (check)"].hover()
        app.menuItems["Restore Selections"].click()

        waitForCommand(containing: "--tags nginx")
        waitForValue("Included", of: tagRow("nginx"))
    }
}
