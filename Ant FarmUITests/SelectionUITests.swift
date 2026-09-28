//
//  SelectionUITests.swift
//  Ant FarmUITests
//

import XCTest

/// Choosing the playbook, hosts, and tags, and how the command follows along.
final class SelectionUITests: AntFarmUITestCase {
    @MainActor
    func testShowsWhatItDiscovered() {
        launchWorkspace()

        for host in ["db1", "web1", "web2"] {
            XCTAssertEqual(hostRow(host).value as? String, "Not selected", host)
        }
        XCTAssertTrue(hostList.buttons["web, 2"].exists)
        XCTAssertTrue(hostList.buttons["db, 1"].exists)

        XCTAssertTrue(tagRow("nginx").waitForExistence(timeout: 5))
        XCTAssertTrue(tagRow("deploy").exists)
        XCTAssertTrue(tagRow("setup").exists)

        XCTAssertEqual(window.popUpButtons["Playbook"].value as? String, "deploy.yml")
        XCTAssertEqual(window.popUpButtons["Inventory"].value as? String, "hosts")
        waitForCommand(containing: "ansible-playbook -i hosts --check --diff deploy.yml")
    }

    @MainActor
    func testChoosingAPlaybook() {
        launchWorkspace()

        window.popUpButtons["Playbook"].click()
        app.menuItems["site.yml"].click()

        waitForCommand(containing: "site.yml")
        // The plan comes from the fake `--list-tasks` output.
        XCTAssertTrue(window.staticTexts["Web servers"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.staticTexts["Install nginx"].exists)
    }

    @MainActor
    func testClickingHostsLimitsTheRun() {
        launchWorkspace()

        hostRow("web1").click()
        waitForValue("Included", of: hostRow("web1"))
        waitForCommand(containing: "--limit web1")

        XCUIElement.perform(withKeyModifiers: .option) {
            hostRow("db1").click()
        }
        waitForValue("Excluded", of: hostRow("db1"))
        waitForCommand(containing: "--limit 'web1,!db1'")

        hostRow("web1").click()
        waitForValue("Not selected", of: hostRow("web1"))
        waitForCommand(containing: "--limit '!db1'")
    }

    @MainActor
    func testIncludingAGroupCoversItsHosts() {
        launchWorkspace()

        hostList.buttons["web, 2"].click()

        waitForCommand(containing: "--limit web")
        waitForValue("Included with a group it's in", of: hostRow("web1"))
        waitForValue("Included with a group it's in", of: hostRow("web2"))
        XCTAssertEqual(hostRow("db1").value as? String, "Not selected")
    }

    @MainActor
    func testUndoRestoresTheSelection() {
        launchWorkspace()

        hostRow("web2").click()
        waitForCommand(containing: "--limit web2")

        app.typeKey("z", modifierFlags: .command)
        waitForValue("Not selected", of: hostRow("web2"))
        waitForCommand(containing: "--limit", false)

        app.typeKey("z", modifierFlags: [.command, .shift])
        waitForValue("Included", of: hostRow("web2"))
        waitForCommand(containing: "--limit web2")
    }

    @MainActor
    func testClearingHosts() {
        launchWorkspace()

        hostRow("web1").click()
        hostRow("web2").click()
        waitForCommand(containing: "--limit web1,web2")

        window.buttons["Clear"].firstMatch.click()

        waitForCommand(containing: "--limit", false)
        XCTAssertEqual(hostRow("web1").value as? String, "Not selected")
        XCTAssertTrue(window.staticTexts["Runs on all hosts"].exists)
    }

    @MainActor
    func testFilteringHosts() {
        launchWorkspace()

        // Edit > Filter Hosts
        app.typeKey("f", modifierFlags: [.command, .option])
        app.typeText("web")

        waitForNonexistence(of: hostRow("db1"))
        XCTAssertTrue(hostRow("web1").exists)
        XCTAssertTrue(hostRow("web2").exists)

        window.buttons["Clear Filter"].click()
        XCTAssertTrue(hostRow("db1").waitForExistence(timeout: 5))
    }

    @MainActor
    func testClickingTagsChoosesWhatRuns() {
        launchWorkspace()
        XCTAssertTrue(tagRow("nginx").waitForExistence(timeout: 5))

        tagRow("nginx").click()
        waitForValue("Included", of: tagRow("nginx"))
        waitForCommand(containing: "--tags nginx")

        XCUIElement.perform(withKeyModifiers: .option) {
            tagRow("setup").click()
        }
        waitForValue("Excluded", of: tagRow("setup"))
        waitForCommand(containing: "--skip-tags setup")
    }

    @MainActor
    func testFilteringTags() {
        launchWorkspace()
        XCTAssertTrue(tagRow("nginx").waitForExistence(timeout: 5))

        // Edit > Filter Tags
        app.typeKey("f", modifierFlags: [.command, .option, .shift])
        app.typeText("dep")

        waitForNonexistence(of: tagRow("nginx"))
        XCTAssertTrue(tagRow("deploy").exists)
    }

    @MainActor
    func testExtraArguments() {
        launchWorkspace()

        let field = window.textFields["Extra arguments, e.g. -e env=staging"]
        field.click()
        field.typeText("-e env=staging")

        waitForCommand(containing: "-e env=staging deploy.yml")
    }

    @MainActor
    func testSwitchingToLiveMode() {
        launchWorkspace()
        waitForCommand(containing: "--check")

        window.toolbars.radioButtons["Live"].click()
        waitForCommand(containing: "--check", false)

        // Run > Check Mode
        app.typeKey("1", modifierFlags: .command)
        waitForCommand(containing: "--check")
        XCTAssertEqual(window.toolbars.radioButtons["Check"].value as? Int, 1)
    }

    @MainActor
    func testSelectionsAreRememberedPerFolder() {
        launchWorkspace()
        hostRow("web1").click()
        tagRow("deploy").click()
        waitForCommand(containing: "--tags deploy --limit web1")

        app.terminate()
        launchWorkspace(environment: ["ANTFARM_UI_TESTING_KEEP_SETTINGS": "1"])

        waitForCommand(containing: "--tags deploy --limit web1", timeout: 10)
        XCTAssertEqual(hostRow("web1").value as? String, "Included")
    }
}
