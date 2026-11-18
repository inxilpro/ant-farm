//
//  LinkUITests.swift
//  Ant FarmUITests
//

import XCTest

/// Opening `antfarm://` links.
final class LinkUITests: AntFarmUITestCase {
    /// Makes the fixture a clone of `example/infrastructure`, as far as Ant Farm can tell.
    private func makeClone() throws {
        let git = fixture.folder.appending(path: ".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:example/infrastructure.git\n"
            .write(to: git.appending(path: "config"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testRepositoryLinkOpensARecentCloneWithItsSelections() throws {
        try makeClone()
        launch(recents: [fixture.folder])
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        app.open(URL(string: "antfarm://open?repo=example/infrastructure&playbook=site.yml&limit=web,!web2&tags[]=nginx")!)

        waitForCommand(containing: "ansible-playbook -i hosts --check --diff --tags nginx --limit 'web,!web2' site.yml", timeout: 10)
        XCTAssertEqual(window.popUpButtons["Playbook"].value as? String, "site.yml")
        waitForValue("Included", of: tagRow("nginx"))
    }

    @MainActor
    func testLinkReplacesTheSelectionsOfAnOpenWindow() {
        launchWorkspace()
        hostRow("db1").click()
        waitForCommand(containing: "--limit db1")

        app.open(URL(string: "antfarm://open?path=\(fixture.folder.path)&limit=web1")!)

        waitForCommand(containing: "--limit web1 deploy.yml")
        XCTAssertEqual(app.windows.count, 1)
    }

    @MainActor
    func testReportsWhatDoesNotApply() {
        launchWorkspace()

        app.open(URL(string: "antfarm://open?path=\(fixture.folder.path)&playbook=site.yml&limit=web1,nope&tags=deploy,missing")!)

        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertTrue(sheet.staticTexts["Not in the inventory, so left out: nope.\nNot tags in the playbook, so left out: missing."].exists)
        sheet.buttons["OK"].click()
        waitForCommand(containing: "--tags deploy --limit web1 site.yml")
    }
}
