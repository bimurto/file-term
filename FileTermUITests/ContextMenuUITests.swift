import XCTest

final class ContextMenuUITests: XCTestCase {
  private var root: URL!
  private let suite = "com.fileterm.tests.contextmenu.\(UUID().uuidString)"
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("child".utf8).write(to: folder.appendingPathComponent("child.txt"))
    try Data("alpha".utf8).write(to: root.appendingPathComponent("alpha.txt"))
    try Data("beta".utf8).write(to: root.appendingPathComponent("beta.txt"))
    app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launch()
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
  }

  override func tearDownWithError() throws {
    app?.terminate()
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  private var list: XCUIElement { app.outlines["fileList"] }
  private func item(_ id: String) -> XCUIElement { app.menuItems["context." + id] }

  private func assertSelected(_ text: String, line: UInt = #line) {
    let summary = app.staticTexts["selectedSize"].firstMatch
    XCTAssertTrue(summary.waitForExistence(timeout: 5), line: line)
    XCTAssertTrue(
      ((summary.value as? String) ?? summary.label).hasPrefix(text), "\(summary.label)", line: line)
  }

  @MainActor func testFileMenuSelectsTheClickedRowAndNamesIt() {
    list.staticTexts["alpha.txt"].rightClick()
    XCTAssertTrue(item("file.open").waitForExistence(timeout: 5))
    assertSelected("1 selected")
    for id in [
      "Open With", "file.trash", "file.getInfo", "commands.rename", "commands.duplicate",
      "file.makeAlias", "file.quickLook", "file.revealInFinder", "file.share", "Copy Path",
      "view.options", "file.tags",
    ] {
      XCTAssertTrue(item(id).exists, "Missing \(id)")
    }
    XCTAssertEqual(item("commands.compress").title, "Compress \"alpha.txt\"")
    XCTAssertEqual(item("edit.text.copy").title, "Copy \"alpha.txt\"")
    XCTAssertFalse(item("file.openInNewTab").exists)
    XCTAssertFalse(item("Contents").exists)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testFolderMenuListsContentsAndOpensInNewTab() {
    list.staticTexts["folder"].rightClick()
    XCTAssertTrue(item("file.openInNewTab").waitForExistence(timeout: 5))
    item("Contents").hover()
    XCTAssertTrue(app.menuItems["child.txt"].waitForExistence(timeout: 5))
    item("file.openInNewTab").click()
    XCTAssertTrue(list.staticTexts["child.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["tab.folder"].exists || app.staticTexts["folder"].exists)
  }

  @MainActor func testRightClickInsideASelectionKeepsIt() {
    list.staticTexts["alpha.txt"].click()
    XCUIElement.perform(withKeyModifiers: .command) { list.staticTexts["beta.txt"].click() }
    list.staticTexts["beta.txt"].rightClick()
    XCTAssertTrue(item("file.newFolderWithSelection").waitForExistence(timeout: 5))
    assertSelected("2 selected")
    XCTAssertEqual(item("commands.rename").title, "Rename 2 Items…")
    XCTAssertEqual(item("commands.compress").title, "Compress 2 Items")
    XCTAssertEqual(item("edit.text.copy").title, "Copy 2 Items")
    XCTAssertFalse(item("file.openInNewTab").exists)
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testRightClickOutsideASelectionReplacesIt() {
    list.staticTexts["alpha.txt"].click()
    XCUIElement.perform(withKeyModifiers: .command) { list.staticTexts["beta.txt"].click() }
    list.staticTexts["folder"].rightClick()
    XCTAssertTrue(item("file.openInNewTab").waitForExistence(timeout: 5))
    assertSelected("1 selected")
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testEmptySpaceOffersTheFolderMenu() {
    list.staticTexts["alpha.txt"].click()
    list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).rightClick()
    XCTAssertTrue(item("file.newFolder").waitForExistence(timeout: 5))
    XCTAssertTrue(item("file.newFile").exists)
    XCTAssertTrue(item("file.getInfo").isEnabled)
    XCTAssertFalse(item("file.trash").exists)
    item("file.newFolder").click()
    XCTAssertTrue(list.textFields["rename.untitled folder"].waitForExistence(timeout: 5))
  }

  @MainActor func testTagDotTurnsATagOnForTheSelection() throws {
    list.staticTexts["alpha.txt"].rightClick()
    let dot = app.buttons["context.file.tag.Red"]
    XCTAssertTrue(dot.waitForExistence(timeout: 5))
    dot.click()
    let predicate = NSPredicate { [root] _, _ in
      let url = root!.appendingPathComponent("alpha.txt")
      let tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
      return tags.contains("Red")
    }
    wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5)
  }

  @MainActor func testIconViewUsesTheSameMenuAndSelectionRule() {
    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["view.asIcons"].click()
    let icon = app.descendants(matching: .any)["icon.alpha.txt"]
    XCTAssertTrue(icon.waitForExistence(timeout: 5))
    icon.rightClick()
    XCTAssertTrue(item("commands.rename").waitForExistence(timeout: 5))
    assertSelected("1 selected")
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testColumnViewUsesTheSameMenu() {
    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["view.asColumns"].click()
    let row = app.staticTexts["beta.txt"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.rightClick()
    XCTAssertTrue(item("commands.rename").waitForExistence(timeout: 5))
    assertSelected("1 selected")
    app.typeKey(.escape, modifierFlags: [])
  }
}
