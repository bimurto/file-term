import XCTest

final class WorkspaceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  @MainActor func testViewModesGroupingSortingAndOptions() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 10))
    app.buttons["view.asIcons"].click()
    XCTAssertTrue(app.scrollViews["iconGrid"].waitForExistence(timeout: 5))
    capture(app, name: "M02 icon grid")
    app.scrollViews["iconGrid"].staticTexts["Child"].doubleClick()
    XCTAssertTrue(app.staticTexts["inside.txt"].waitForExistence(timeout: 5))
    app.buttons["go.back"].click()
    app.buttons["view.asColumns"].click()
    XCTAssertTrue(app.descendants(matching: .any)["columnBrowser"].waitForExistence(timeout: 5))
    let column = app.descendants(matching: .any)["columnBrowser"]
    let child = column.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Child"))
      .firstMatch
    XCTAssertTrue(child.waitForExistence(timeout: 10))
    child.click()
    XCTAssertTrue(column.buttons["inside.txt"].waitForExistence(timeout: 5))
    capture(app, name: "M02 hierarchy columns")
    app.buttons["go.back"].click()
    app.buttons["view.asList"].click()
    let size = app.outlines["fileList"].buttons["Size"]
    size.click()
    XCTAssertTrue(
      app.outlines["fileList"].children(matching: .outlineRow).element(boundBy: 1).staticTexts[
        "small.txt"
      ].exists)
    menu("View", submenu: "Group by", command: "Kind", app: app)
    XCTAssertTrue(
      app.outlines["fileList"].staticTexts["groupHeader.TXT File"].waitForExistence(timeout: 5))
    menu("View", command: "Show View Options", app: app)
    XCTAssertTrue(
      app.staticTexts["Applies to this tab across folders."].waitForExistence(timeout: 5))
    app.buttons["Apply"].click()
    menu("View", submenu: "Group by", command: "None", app: app)
    capture(app, name: "M02 sortable list")
  }

  @MainActor func testPinnedTabsMultipleWindowsAndNativeWindowMenu() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.outlines["fileList"].staticTexts["Child"].waitForExistence(timeout: 10))
    menu("Window", command: "Pin View", app: app)
    app.outlines["fileList"].staticTexts["Child"].doubleClick()
    XCTAssertTrue(app.outlines["fileList"].staticTexts["inside.txt"].waitForExistence(timeout: 5))
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab.first.")).count, 2)
    app.typeKey("1", modifierFlags: .command)
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 5))
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(app.outlines["fileList"].staticTexts["inside.txt"].waitForExistence(timeout: 5))
    app.typeKey("n", modifierFlags: .command)
    XCTAssertTrue(
      app.windows.matching(identifier: "browserWindow").element(boundBy: 1).waitForExistence(
        timeout: 10))
    XCTAssertEqual(app.windows.matching(identifier: "browserWindow").count, 2)
    let front = app.windows.matching(identifier: "browserWindow").element(boundBy: 0)
    XCTAssertTrue(front.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 5))
    front.buttons["go.toFolder"].click()
    XCTAssertEqual(app.sheets.count, 1)
    app.buttons["Cancel"].click()
    app.menuBars.menuBarItems["Window"].click()
    if #available(macOS 15, *) {
      XCTAssertTrue(app.menuItems["Fill"].exists)
      XCTAssertTrue(app.menuItems["Center"].exists)
      XCTAssertTrue(app.menuItems["Move & Resize"].exists)
      XCTAssertTrue(app.menuItems["Full Screen Tile"].exists)
    }
    XCTAssertTrue(app.menuItems["Bring All to Front"].exists)
    app.typeKey(.escape, modifierFlags: [])
    app.typeKey("w", modifierFlags: [.command, .shift])
    let closed = expectation(
      for: NSPredicate(format: "count == 1"),
      evaluatedWith: app.windows.matching(identifier: "browserWindow"))
    wait(for: [closed], timeout: 5)
    XCTAssertTrue(app.outlines["fileList"].staticTexts["inside.txt"].exists)
  }

  @MainActor func testCustomizationAndQuitKeepWindowsRestore() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 10))
    menu("View", command: "Customize Toolbar…", app: app)
    XCTAssertTrue(app.buttons["Restore Default Toolbar"].waitForExistence(timeout: 5))
    app.buttons["Done"].click()
    menu("View", command: "Show Sidebar Editor", app: app)
    XCTAssertTrue(app.staticTexts["Sidebar Editor"].waitForExistence(timeout: 5))
    app.buttons["Done"].click()
    menu("View", command: "Show Sidebar", app: app)
    XCTAssertFalse(app.outlines["navigationSidebar"].exists)
    menu("View", command: "Show Sidebar", app: app)
    app.typeKey("t", modifierFlags: .command)
    app.outlines["fileList"].staticTexts["Child"].doubleClick()
    XCTAssertTrue(app.outlines["fileList"].staticTexts["inside.txt"].waitForExistence(timeout: 5))
    app.buttons["view.horizontal"].click()
    menu("FileTerm", command: "Quit and Keep Windows", app: app)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launch()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").element(boundBy: 0).staticTexts["inside.txt"]
        .waitForExistence(timeout: 10))
    XCTAssertEqual(app.outlines.matching(identifier: "fileList").count, 2)
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab.first.")).count, 2)
  }

  @MainActor func testStartingDirectoryAndOptionalSessionRestore() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let restore = app.checkBoxes["Restore windows and tabs on startup"]
    XCTAssertTrue(restore.waitForExistence(timeout: 5))
    XCTAssertEqual((restore.value as? NSNumber)?.intValue, 0)
    let directory = app.textFields.firstMatch
    directory.click()
    directory.typeKey("a", modifierFlags: .command)
    directory.typeText(fixture.root.appendingPathComponent("Child").path)
    app.buttons["Set Starting Directory"].click()
    let expectedDirectory =
      "Current: " + fixture.root.appendingPathComponent("Child").resolvingSymlinksInPath().path
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label == %@ OR value == %@", expectedDirectory, expectedDirectory)
      ).firstMatch.waitForExistence(timeout: 5))
    let saved = expectation(
      for: NSPredicate(format: "enabled == true"),
      evaluatedWith: app.buttons["Set Starting Directory"])
    wait(for: [saved], timeout: 5)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].exists)
    menu("FileTerm", command: "Quit FileTerm", app: app)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launchEnvironment.removeValue(forKey: "FILETERM_INITIAL_DIRECTORY")
    app.launch()
    XCTAssertTrue(app.outlines["fileList"].staticTexts["inside.txt"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.outlines["fileList"].staticTexts["small.txt"].exists)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(restore.waitForExistence(timeout: 5))
    restore.click()
    app.typeKey("w", modifierFlags: .command)
    app.buttons["go.toFolder"].click()
    let path = app.textFields["goToFolderPath"]
    XCTAssertTrue(path.waitForExistence(timeout: 5))
    path.click()
    path.typeKey("a", modifierFlags: .command)
    path.typeText(fixture.root.path)
    path.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.outlines["fileList"].staticTexts["small.txt"].waitForExistence(timeout: 5))
    app.typeKey("t", modifierFlags: .command)
    app.buttons["view.vertical"].click()
    app.buttons["view.asIcons"].click()
    app.typeKey("n", modifierFlags: .command)
    XCTAssertTrue(
      app.windows.matching(identifier: "browserWindow").element(boundBy: 1).waitForExistence(
        timeout: 10))
    XCTAssertTrue(
      app.windows.element(boundBy: 0).outlines["fileList"].staticTexts["inside.txt"]
        .waitForExistence(timeout: 5))
    menu("FileTerm", command: "Quit FileTerm", app: app)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    app.launch()
    XCTAssertTrue(
      app.windows.matching(identifier: "browserWindow").element(boundBy: 1).waitForExistence(
        timeout: 10))
    XCTAssertTrue(app.scrollViews["iconGrid"].waitForExistence(timeout: 10))
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab.first.")).count, 3)
  }

  @MainActor private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func menu(
    _ title: String, submenu: String? = nil, command: String, app: XCUIApplication
  ) {
    app.menuBars.menuBarItems[title].click()
    if let submenu {
      app.menuItems[submenu].hover()
      app.menuItems[submenu].menuItems[command].click()
    } else {
      app.menuItems[command].click()
    }
  }
}

private struct WorkspaceFixture {
  let root: URL
  let suite = "com.fileterm.uitests.\(UUID().uuidString)"
  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Child"), withIntermediateDirectories: true)
    try Data("small".utf8).write(to: root.appendingPathComponent("small.txt"))
    try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("large.txt"))
    try Data().write(to: root.appendingPathComponent("Child/inside.txt"))
  }
  @MainActor func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launch()
    return app
  }
  func remove() {
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}
