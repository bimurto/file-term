import XCTest

final class FileOperationsUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor func testNewFolderSubmitsInlineName() throws {
    let fixture = try FileOperationsFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    list.staticTexts["alpha.txt"].click()
    menu("File", command: "New Folder", app: app)

    let editor = list.textFields["rename.untitled folder"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("untitled folder").path))
    replaceName(in: editor, with: "Project Notes")
    editor.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(list.staticTexts["Project Notes"].waitForExistence(timeout: 5))
    XCTAssertFalse(editor.exists)
    let folder = fixture.root.appendingPathComponent("Project Notes")
    XCTAssertEqual(try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("untitled folder").path))
  }

  @MainActor func testNewFileInlineNameIncludesEditableExtension() throws {
    let fixture = try FileOperationsFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    list.staticTexts["alpha.txt"].click()
    menu("File", command: "New File", app: app)

    let editor = list.textFields["rename.untitled"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("untitled").path))
    replaceName(in: editor, with: "notes.md")
    editor.typeKey(.return, modifierFlags: [])

    // Adding an extension uses the same explicit confirmation as changing an existing one.
    let confirm = app.dialogs.buttons["Change Extension"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.click()

    XCTAssertTrue(list.staticTexts["notes.md"].waitForExistence(timeout: 5))
    XCTAssertFalse(editor.exists)
    let file = fixture.root.appendingPathComponent("notes.md")
    XCTAssertEqual(try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, true)
    XCTAssertEqual(try Data(contentsOf: file), Data())
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("untitled").path))
  }

  @MainActor func testSingleRenameAndUndoRestoresOriginalFile() throws {
    let fixture = try FileOperationsFixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }

    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    list.staticTexts["alpha.txt"].click()
    menu("Commands", command: "Rename", app: app)

    let editor = list.textFields["rename.alpha.txt"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("alpha.txt").path))
    replaceName(in: editor, with: "renamed.txt")
    editor.typeKey(.return, modifierFlags: [])

    let renamed = list.staticTexts["renamed.txt"]
    XCTAssertTrue(renamed.waitForExistence(timeout: 5))
    XCTAssertFalse(list.staticTexts["alpha.txt"].exists)
    XCTAssertEqual(
      try Data(contentsOf: fixture.root.appendingPathComponent("renamed.txt")), Data("alpha".utf8))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("alpha.txt").path))

    // Leave the text editor so Undo targets file history rather than text editing.
    renamed.click()
    menu("Edit", command: "Undo", app: app)

    XCTAssertTrue(list.staticTexts["alpha.txt"].waitForExistence(timeout: 5))
    XCTAssertFalse(list.staticTexts["renamed.txt"].exists)
    XCTAssertEqual(
      try Data(contentsOf: fixture.root.appendingPathComponent("alpha.txt")), Data("alpha".utf8))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.root.appendingPathComponent("renamed.txt").path))
  }

  @MainActor private func replaceName(in editor: XCUIElement, with name: String) {
    editor.click()
    let focused = expectation(
      for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)
    wait(for: [focused], timeout: 5)
    editor.typeKey("a", modifierFlags: .command)
    editor.typeText(name)
  }

  @MainActor private func menu(_ title: String, command: String, app: XCUIApplication) {
    app.menuBars.menuBarItems[title].click()
    let item = app.menuItems[command]
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: item)
    wait(for: [enabled], timeout: 5)
    item.click()
  }
}

private struct FileOperationsFixture {
  let root: URL
  let suite = "com.fileterm.uitests.\(UUID().uuidString)"

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("alpha".utf8).write(to: root.appendingPathComponent("alpha.txt"))
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
