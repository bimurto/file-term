import XCTest

final class AppearanceUITests: XCTestCase {
  private var root: URL!
  private var suite: String!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("left"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("left/Target"), withIntermediateDirectories: true)
    try Data("sample".utf8).write(to: root.appendingPathComponent("left/sample.txt"))
    suite = "com.fileterm.m12.\(UUID().uuidString)"
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  @MainActor private func launch(environment: [String: String] = [:]) -> XCUIApplication {
    let app = XCUIApplication()
    // A crash in an earlier run would otherwise block launch with the system's reopen dialog.
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.appendingPathComponent("left").path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    for (key, value) in environment { app.launchEnvironment[key] = value }
    app.launch()
    addTeardownBlock { app.terminate() }
    return app
  }

  @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor func testThemesApplyAndPersist() throws {
    let app = launch()
    XCTAssertTrue(app.staticTexts["sample.txt"].firstMatch.waitForExistence(timeout: 10))
    screenshot(app, "default-theme")
    app.typeKey(",", modifierFlags: .command)
    let tab = app.buttons["settingsTab.Themes"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    for id in [
      "default", "dark", "light", "forklift", "bluerange", "dracula", "commander", "sand",
      "polar-night",
    ] {
      XCTAssertTrue(app.staticTexts["theme.\(id)"].waitForExistence(timeout: 5), id)
    }
    app.staticTexts["theme.dracula"].click()
    screenshot(app, "themes-settings")
    app.typeKey("w", modifierFlags: .command)
    sleep(1)
    screenshot(app, "dracula-browser")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["sample.txt"].firstMatch.waitForExistence(timeout: 10))
    sleep(1)
    screenshot(app, "dracula-after-relaunch")
  }

  @MainActor func testTagsCanBeAddedRemovedAndAppearInTheSidebar() throws {
    let app = launch()
    let sidebar = app.descendants(matching: .any)["navigationSidebar"]
    XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
    for name in ["Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"] {
      XCTAssertTrue(sidebar.descendants(matching: .any)["sidebarTag.\(name)"].exists, name)
    }
    app.typeKey(",", modifierFlags: .command)
    let tab = app.buttons["settingsTab.Tags"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    let name = app.textFields["newTagName"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["addTag"].isEnabled)
    name.click()
    name.typeText("Work")
    app.buttons["addTag"].click()
    XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 5))
    screenshot(app, "tags-settings")
    app.buttons["removeTag.Gray"].click()
    XCTAssertFalse(app.buttons["removeTag.Gray"].waitForExistence(timeout: 1))
    XCTAssertTrue(sidebar.descendants(matching: .any)["sidebarTag.Work"].exists)
    XCTAssertFalse(sidebar.descendants(matching: .any)["sidebarTag.Gray"].exists)
  }

  @MainActor func testClickingATagOpensAResultScope() throws {
    let app = launch()
    let tag = app.descendants(matching: .any)["sidebarTag.Red"]
    XCTAssertTrue(tag.waitForExistence(timeout: 10))
    tag.click()
    XCTAssertTrue(app.buttons["closeSearch"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["searchSummary"].exists)
    app.buttons["closeSearch"].click()
    XCTAssertTrue(app.staticTexts["sample.txt"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor private func dropSampleOnSecondPane(_ app: XCUIApplication) throws {
    let second = app.descendants(matching: .any)["pane.second"]
    XCTAssertTrue(second.waitForExistence(timeout: 10))
    second.staticTexts["Target"].firstMatch.doubleClick()
    XCTAssertTrue(second.staticTexts["This folder is empty"].waitForExistence(timeout: 5))
    let sample = app.descendants(matching: .any)["pane.first"].staticTexts["sample.txt"].firstMatch
    sample.click()
    sample.press(forDuration: 0.6, thenDragTo: second.staticTexts["This folder is empty"])
  }

  @MainActor func testADropWithoutConfirmationMovesOnTheSameVolume() throws {
    let app = launch()
    app.buttons["view.vertical"].firstMatch.click()
    try dropSampleOnSecondPane(app)
    let moved = root.appendingPathComponent("left/Target/sample.txt")
    let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: moved.path) }
    wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: 10)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("left/sample.txt").path))
  }

  @MainActor func testADropAsksForCopyOrMoveWhenTheSettingIsOn() throws {
    let app = launch()
    app.typeKey(",", modifierFlags: .command)
    let toggle = app.checkBoxes["askBeforeDrag"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.value as? Int, 0)
    toggle.click()
    XCTAssertEqual(app.checkBoxes["automaticUpdateChecks"].value as? Int, 0)
    XCTAssertTrue(app.buttons["checkForUpdatesNow"].exists)
    screenshot(app, "general-settings")
    app.typeKey("w", modifierFlags: .command)
    app.buttons["view.vertical"].firstMatch.click()
    try dropSampleOnSecondPane(app)
    let copy = app.sheets.buttons["Copy"]
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    XCTAssertTrue(app.sheets.buttons["Move"].exists)
    screenshot(app, "drop-confirmation")
    copy.click()
    let copied = root.appendingPathComponent("left/Target/sample.txt")
    let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: copied.path) }
    wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: 10)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent("left/sample.txt").path))
  }

  @MainActor func testMenusIncludeSystemItemsUpdatesAndServices() throws {
    let app = launch()
    XCTAssertTrue(app.staticTexts["sample.txt"].firstMatch.waitForExistence(timeout: 10))
    app.menuBars.menuBarItems["FileTerm"].click()
    XCTAssertTrue(app.menuItems["Check for Updates…"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.menuItems["About FileTerm"].exists)
    XCTAssertTrue(app.menuItems["Services"].exists)
    app.typeKey(.escape, modifierFlags: [])
    for _ in 0..<2 {
      app.menuBars.menuBarItems["Edit"].click()
      XCTAssertTrue(app.menuItems["Select All"].waitForExistence(timeout: 5))
      XCTAssertEqual(
        app.menuItems.matching(NSPredicate(format: "title == 'Emoji & Symbols'")).count, 1)
      XCTAssertTrue(
        app.menuItems.matching(NSPredicate(format: "title CONTAINS 'Dictation'")).count > 0,
        "Dictation")
      app.typeKey(.escape, modifierFlags: [])
    }
    app.menuBars.menuBarItems["File"].click()
    XCTAssertTrue(app.menuItems["file.share"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.menuItems["file.share"].isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    app.staticTexts["sample.txt"].firstMatch.click()
    app.menuBars.menuBarItems["File"].click()
    XCTAssertTrue(app.menuItems["file.share"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.menuItems["file.share"].isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    app.menuBars.menuBarItems["FileTerm"].click()
    app.menuItems["Services"].hover()
    let services = app.menuItems["Services"].menuItems
    XCTAssertTrue(services.firstMatch.waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
    app.typeKey(.escape, modifierFlags: [])
    app.menuBars.menuBarItems["FileTerm"].click()
    app.menuItems["About FileTerm"].click()
    let version = app.staticTexts.matching(NSPredicate(format: "value CONTAINS '0.1.0 (1)'"))
    XCTAssertTrue(version.firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor func testOnboardingExplainsPermissions() throws {
    let app = launch(environment: ["FILETERM_SHOW_ONBOARDING": "1"])
    let done = app.buttons["finishOnboarding"]
    XCTAssertTrue(done.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Full Disk Access"].exists)
    XCTAssertTrue(app.buttons["openFullDiskAccess"].exists)
    XCTAssertTrue(app.buttons["allowNotifications"].exists)
    let window = app.windows["onboardingWindow"]
    let shot = XCTAttachment(screenshot: window.screenshot())
    shot.name = "onboarding"
    shot.lifetime = .keepAlways
    add(shot)
    done.click()
    XCTAssertFalse(done.waitForExistence(timeout: 1))
  }
}
