import XCTest

final class SelectionSearchUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor func testSelectionInvertAndQuickSelectPreview() throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    list.staticTexts["alpha.txt"].click()
    XCTAssertTrue(app.staticTexts["selectedSize"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      (app.staticTexts["selectedSize"].value as? String ?? app.staticTexts["selectedSize"].label)
        .contains("1 selected"))

    menu("Edit", command: "Invert Selection", app: app)
    XCTAssertTrue(
      (app.staticTexts["selectedSize"].value as? String ?? app.staticTexts["selectedSize"].label)
        .contains("2 selected"))

    menu("Edit", command: "Deselect All", app: app)
    XCTAssertFalse(app.staticTexts["selectedSize"].exists)

    app.typeKey("s", modifierFlags: .command)
    let pattern = app.textFields["quickSelectPattern"]
    XCTAssertTrue(pattern.waitForExistence(timeout: 5))
    pattern.typeText("*.txt")
    let count = app.staticTexts["quickSelectCount"]
    XCTAssertTrue(count.waitForExistence(timeout: 5))
    XCTAssertTrue((count.value as? String ?? count.label).contains("1 of 3 items will be selected"))
    app.buttons["Select"].click()
    XCTAssertTrue(app.staticTexts["selectedSize"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      (app.staticTexts["selectedSize"].value as? String ?? app.staticTexts["selectedSize"].label)
        .contains("1 selected"))
    XCTAssertTrue(list.staticTexts["beta.md"].exists)
  }

  @MainActor func testQuickOpenFindsCommandsAndFolders() throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    XCTAssertTrue(app.outlines["fileList"].staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    app.outlines["fileList"].staticTexts["alpha.txt"].click()
    app.typeKey(.escape, modifierFlags: [])
    let field = app.textFields["quickOpenField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.typeText("Select All")
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["selectedSize"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      (app.staticTexts["selectedSize"].value as? String ?? app.staticTexts["selectedSize"].label)
        .contains("3 selected"))

    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.typeText("Sub")
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.outlines["fileList"].staticTexts["nested.log"].waitForExistence(timeout: 5))
  }

  @MainActor func testSearchShowHiddenAndRefresh() throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertFalse(list.staticTexts[".hidden"].exists)

    app.toolbarButton("showHiddenToggle").click()
    XCTAssertTrue(list.staticTexts[".hidden"].waitForExistence(timeout: 5))
    app.toolbarButton("showHiddenToggle").click()
    let hiddenGone = expectation(
      for: NSPredicate(format: "exists == false"), evaluatedWith: list.staticTexts[".hidden"])
    wait(for: [hiddenGone], timeout: 5)

    try Data("fresh".utf8).write(to: fixture.root.appendingPathComponent("added.txt"))
    menu("View", command: "Refresh", app: app)
    XCTAssertTrue(list.staticTexts["added.txt"].waitForExistence(timeout: 5))

    app.typeKey("f", modifierFlags: .command)
    let search = app.textFields["searchField"]
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.typeText("nested")
    search.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.buttons["closeSearch"].waitForExistence(timeout: 5))
    XCTAssertTrue(list.staticTexts["nested.log"].waitForExistence(timeout: 5))
    XCTAssertFalse(list.staticTexts["alpha.txt"].exists)
    app.buttons["closeSearch"].click()
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 5))
  }

  @MainActor func testShortcutCustomizationAndConflictDetection() throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    XCTAssertTrue(app.outlines["fileList"].staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let shortcutsTab = app.buttons["settingsTab.Shortcuts"]
    XCTAssertTrue(shortcutsTab.waitForExistence(timeout: 5))
    shortcutsTab.click()

    let search = app.textFields["shortcutSearch"]
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    for (query, id) in [
      ("Quick Select", "select.quick"),
      ("Quick Open", "quickOpen"),
      ("New Folder", "file.newFolder"),
      ("New Folder With Selection", "file.newFolderWithSelection"),
      ("New File", "file.newFile"),
      ("Open", "file.open"),
      ("Quick Look", "file.quickLook"),
    ] {
      search.click()
      search.typeKey("a", modifierFlags: .command)
      search.typeText(query)
      XCTAssertTrue(
        app.staticTexts["shortcut.\(id)"].waitForExistence(timeout: 5),
        "Missing seeded shortcut \(id)")
    }
    search.click()
    search.typeKey("a", modifierFlags: .command)
    search.typeText("Quick Select")

    app.buttons["editShortcut.select.quick"].click()
    let recorder = app.buttons["shortcutRecorder"]
    XCTAssertTrue(recorder.waitForExistence(timeout: 5))
    recorder.click()
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(app.staticTexts["shortcutConflict"].waitForExistence(timeout: 5))
    app.buttons["reassignShortcut"].click()
    XCTAssertEqual(
      app.staticTexts["shortcut.select.quick"].value as? String
        ?? app.staticTexts["shortcut.select.quick"].label, "⌘O")
    app.buttons["restoreShortcutDefaults"].click()
    XCTAssertEqual(
      app.staticTexts["shortcut.select.quick"].value as? String
        ?? app.staticTexts["shortcut.select.quick"].label, "⌘S")
  }

  @MainActor private func menu(_ title: String, command: String, app: XCUIApplication) {
    app.menuBars.menuBarItems[title].click()
    app.menuItems[command].click()
  }
}

private struct SelectionFixture {
  let root: URL
  let suite = "com.fileterm.uitests.\(UUID().uuidString)"

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sub = root.appendingPathComponent("Sub")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("alpha".utf8).write(to: root.appendingPathComponent("alpha.txt"))
    try Data("beta".utf8).write(to: root.appendingPathComponent("beta.md"))
    try Data("secret".utf8).write(to: root.appendingPathComponent(".hidden"))
    try Data("nested".utf8).write(to: sub.appendingPathComponent("nested.log"))
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
