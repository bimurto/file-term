import XCTest

final class ContextMenuUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor func testFileMenuSelectsTheClickedRowAndNamesIt() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    fileList(app).staticTexts["alpha.txt"].rightClick()
    XCTAssertTrue(menuItem("file.open", app).waitForExistence(timeout: 5))
    assertSelected("1 selected", app)
    for id in [
      "Open With", "file.trash", "file.getInfo", "commands.rename", "commands.duplicate",
      "file.makeAlias", "file.quickLook", "file.revealInFinder", "file.share", "Copy Path",
      "view.options", "file.tags",
    ] {
      XCTAssertTrue(menuItem(id, app).exists, "Missing \(id)")
    }
    XCTAssertEqual(menuItem("commands.compress", app).title, "Compress \"alpha.txt\"")
    XCTAssertEqual(menuItem("edit.text.copy", app).title, "Copy \"alpha.txt\"")
    XCTAssertFalse(menuItem("file.openInNewTab", app).exists)
    XCTAssertFalse(menuItem("Contents", app).exists)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testFolderMenuListsContentsAndOpensInNewTab() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    fileList(app).staticTexts["folder"].rightClick()
    XCTAssertTrue(menuItem("file.openInNewTab", app).waitForExistence(timeout: 5))
    menuItem("Contents", app).hover()
    XCTAssertTrue(app.menuItems["child.txt"].waitForExistence(timeout: 5))
    menuItem("file.openInNewTab", app).click()
    XCTAssertTrue(fileList(app).staticTexts["child.txt"].waitForExistence(timeout: 5))
  }

  @MainActor func testRightClickInsideASelectionKeepsIt() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    selectAlphaAndBeta(app)
    fileList(app).staticTexts["beta.txt"].rightClick()
    XCTAssertTrue(menuItem("file.newFolderWithSelection", app).waitForExistence(timeout: 5))
    assertSelected("2 selected", app)
    XCTAssertEqual(menuItem("commands.rename", app).title, "Rename 2 Items…")
    XCTAssertEqual(menuItem("commands.compress", app).title, "Compress 2 Items")
    XCTAssertEqual(menuItem("edit.text.copy", app).title, "Copy 2 Items")
    XCTAssertFalse(menuItem("file.openInNewTab", app).exists)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testRightClickOutsideASelectionReplacesIt() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    selectAlphaAndBeta(app)
    fileList(app).staticTexts["folder"].rightClick()
    XCTAssertTrue(menuItem("file.openInNewTab", app).waitForExistence(timeout: 5))
    assertSelected("1 selected", app)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testEmptySpaceOffersTheFolderMenu() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = fileList(app)
    list.staticTexts["alpha.txt"].click()
    list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).rightClick()
    XCTAssertTrue(menuItem("file.newFolder", app).waitForExistence(timeout: 5))
    XCTAssertTrue(menuItem("file.newFile", app).exists)
    XCTAssertTrue(menuItem("file.getInfo", app).isEnabled)
    XCTAssertFalse(menuItem("file.trash", app).exists)
    menuItem("file.newFolder", app).click()
    XCTAssertTrue(list.textFields["rename.untitled folder"].waitForExistence(timeout: 5))
  }

  @MainActor func testTagDotTurnsATagOnForTheSelection() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    fileList(app).staticTexts["alpha.txt"].rightClick()
    let dot = app.buttons["context.file.tag.Red"]
    XCTAssertTrue(dot.waitForExistence(timeout: 5))
    dot.click()
    let file = fixture.root.appendingPathComponent("alpha.txt")
    let deadline = Date().addingTimeInterval(5)
    var tags: [String] = []
    while Date() < deadline, !tags.contains("Red") {
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
      tags = (try? file.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }
    XCTAssertTrue(tags.contains("Red"))
  }

  @MainActor func testIconViewUsesTheSameMenuAndSelectionRule() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["view.asIcons"].click()
    let icon = app.descendants(matching: .any)["icon.alpha.txt"]
    XCTAssertTrue(icon.waitForExistence(timeout: 5))
    icon.rightClick()
    XCTAssertTrue(menuItem("commands.rename", app).waitForExistence(timeout: 5))
    XCTAssertEqual(menuItem("commands.compress", app).title, "Compress \"alpha.txt\"")
    assertSelected("1 selected", app)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testColumnViewUsesTheSameMenu() throws {
    let fixture = try ContextMenuFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["view.asColumns"].click()
    // Column rows are exposed as buttons named after the item.
    let row = app.descendants(matching: .any)["columnBrowser"].buttons["beta.txt"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.rightClick()
    XCTAssertTrue(menuItem("commands.rename", app).waitForExistence(timeout: 5))
    XCTAssertEqual(menuItem("commands.compress", app).title, "Compress \"beta.txt\"")
    assertSelected("1 selected", app)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor private func fileList(_ app: XCUIApplication) -> XCUIElement {
    app.outlines["fileList"]
  }

  @MainActor private func menuItem(_ id: String, _ app: XCUIApplication) -> XCUIElement {
    app.menuItems["context." + id]
  }

  @MainActor private func selectAlphaAndBeta(_ app: XCUIApplication) {
    let list = fileList(app)
    list.staticTexts["alpha.txt"].click()
    XCUIElement.perform(withKeyModifiers: .command) { list.staticTexts["beta.txt"].click() }
  }

  @MainActor private func assertSelected(
    _ text: String, _ app: XCUIApplication, line: UInt = #line
  ) {
    let summary = app.staticTexts["selectedSize"].firstMatch
    XCTAssertTrue(summary.waitForExistence(timeout: 5), line: line)
    let shown = (summary.value as? String) ?? summary.label
    XCTAssertTrue(shown.hasPrefix(text), shown, line: line)
  }
}

private struct ContextMenuFixture {
  let root: URL
  let suite = "com.fileterm.tests.contextmenu.\(UUID().uuidString)"

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("child".utf8).write(to: folder.appendingPathComponent("child.txt"))
    try Data("alpha".utf8).write(to: root.appendingPathComponent("alpha.txt"))
    try Data("beta".utf8).write(to: root.appendingPathComponent("beta.txt"))
  }

  @MainActor func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launch()
    XCTAssertTrue(app.outlines["fileList"].staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    return app
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}
