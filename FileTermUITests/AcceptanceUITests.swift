import XCTest

/// The Guide's practice scenarios, end to end. Each one checks the real files on disk, because what
/// matters is what happened to them and not what the app shows.
final class AcceptanceUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  /// M14.07: the file exists at the destination and is still in the source.
  @MainActor func testCopyPracticeScenario() throws {
    let fixture = try AcceptanceFixture()
    defer { fixture.remove() }
    try fixture.write("practice.txt", in: "left", "practice")
    let app = fixture.launch(in: "left")
    defer { app.terminate() }
    let left = fixture.pane("first", app)
    XCTAssertTrue(left.staticTexts["practice.txt"].waitForExistence(timeout: 10))
    open(fixture.url("right").path, inSecondPaneOf: fixture, app: app)

    left.staticTexts["practice.txt"].click()
    menu("Commands", command: "Copy to…", app: app)
    let destination = "Destination: \(fixture.url("right").path)"
    let prompt = app.staticTexts.matching(
      NSPredicate(format: "label == %@ OR value == %@", destination, destination)
    ).firstMatch
    XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    app.buttons["Copy"].firstMatch.click()

    XCTAssertTrue(
      fixture.pane("second", app).staticTexts["practice.txt"].waitForExistence(timeout: 10))
    let contents = Data("practice".utf8)
    XCTAssertEqual(
      try Data(contentsOf: fixture.url("right").appendingPathComponent("practice.txt")), contents)
    XCTAssertEqual(
      try Data(contentsOf: fixture.url("left").appendingPathComponent("practice.txt")), contents)
  }

  /// M14.08: a Sequence rule shows in the preview, and Cancel leaves the files unchanged.
  @MainActor func testRenamePracticeScenario() throws {
    let fixture = try AcceptanceFixture()
    defer { fixture.remove() }
    try fixture.write("one.txt", in: "left", "one")
    try fixture.write("two.txt", in: "left", "two")
    let before = try fixture.snapshot()
    let app = fixture.launch(in: "left")
    defer { app.terminate() }
    let list = fixture.pane("first", app)
    XCTAssertTrue(list.staticTexts["one.txt"].waitForExistence(timeout: 10))

    list.staticTexts["one.txt"].click()
    app.typeKey("a", modifierFlags: .command)
    menu("Commands", command: "Rename", app: app)
    let add = app.descendants(matching: .any)["renameAddRule"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    add.click()
    app.menuItems["Add Sequence"].click()

    let preview = app.descendants(matching: .any)["renamePreview"]
    XCTAssertTrue(preview.staticTexts["1one.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(preview.staticTexts["2two.txt"].exists)
    XCTAssertTrue(
      shows(app.staticTexts["renameCount"], "2 of 2 items will be renamed"))
    capture(app, name: "M14 rename preview")

    app.sheets.buttons["Cancel"].click()
    XCTAssertTrue(add.waitForNonExistence(timeout: 5))
    XCTAssertEqual(try fixture.snapshot(), before)
    XCTAssertTrue(list.staticTexts["one.txt"].exists)
  }

  /// M14.09: a one-way sync with deletion off proposes adds and updates, and Cancel changes nothing.
  @MainActor func testSyncPracticeScenario() throws {
    let fixture = try AcceptanceFixture()
    defer { fixture.remove() }
    let older = Date(timeIntervalSinceNow: -7200)
    try fixture.write("same.txt", in: "left", "same", modified: older)
    try fixture.write("same.txt", in: "right", "same", modified: older)
    try fixture.write("changed.txt", in: "left", "newer contents")
    try fixture.write("changed.txt", in: "right", "old", modified: older)
    try fixture.write("sub/added.txt", in: "left", "added")
    try fixture.write("orphan.txt", in: "right", "orphan")
    let before = try fixture.snapshot()
    let app = fixture.launch(in: "left")
    defer { app.terminate() }
    XCTAssertTrue(
      fixture.pane("first", app).staticTexts["changed.txt"].waitForExistence(timeout: 10))
    open(fixture.url("right").path, inSecondPaneOf: fixture, app: app)
    fixture.pane("first", app).staticTexts["changed.txt"].click()

    menu("Commands", command: "Sync to…", app: app)
    let actions = app.descendants(matching: .any)["syncActions"]
    XCTAssertTrue(actions.waitForExistence(timeout: 5))
    let deletion = app.checkBoxes["syncDeleteOrphans"]
    XCTAssertTrue(deletion.waitForExistence(timeout: 5))
    XCTAssertEqual(deletion.value as? Int, 0)

    XCTAssertTrue(actions.staticTexts["changed.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(actions.staticTexts["sub/added.txt"].waitForExistence(timeout: 5))
    XCTAssertFalse(actions.staticTexts["orphan.txt"].exists)
    XCTAssertFalse(actions.staticTexts["same.txt"].exists)
    capture(app, name: "M14 sync proposal")

    app.sheets.buttons["Cancel"].click()
    XCTAssertTrue(actions.waitForNonExistence(timeout: 5))
    XCTAssertEqual(try fixture.snapshot(), before)
  }

  @MainActor private func open(
    _ path: String, inSecondPaneOf fixture: AcceptanceFixture, app: XCUIApplication
  ) {
    app.radioButtons["Vertical — Side by Side"].click()
    let second = fixture.pane("second", app)
    XCTAssertTrue(second.waitForExistence(timeout: 5))
    second.click()
    app.toolbarButton("go.toFolder").click()
    let field = app.textFields["goToFolderPath"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(path)
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(field.waitForNonExistence(timeout: 5))
  }

  @MainActor private func shows(_ element: XCUIElement, _ text: String) -> Bool {
    let predicate = NSPredicate(format: "label == %@ OR value == %@", text, text)
    let wait = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [wait], timeout: 5) == .completed
  }

  @MainActor private func capture(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
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

/// Two disposable folders, "left" and "right", under one temporary root.
private struct AcceptanceFixture {
  struct Item: Equatable {
    let contents: Data?
    let modified: Date?
  }

  let root: URL
  let suite = "com.fileterm.uitests.\(UUID().uuidString)"

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    for folder in ["left", "right"] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
  }

  func url(_ folder: String) -> URL { root.appendingPathComponent(folder) }

  func write(_ path: String, in folder: String, _ text: String, modified: Date? = nil) throws {
    let file = url(folder).appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
    if let modified {
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }
  }

  /// Everything under the root with its contents and date, to prove that nothing changed.
  func snapshot() throws -> [String: Item] {
    var items: [String: Item] = [:]
    let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
    let walker = try XCTUnwrap(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
    for case let url as URL in walker {
      let values = try url.resourceValues(forKeys: Set(keys))
      items[url.path] = Item(
        contents: values.isDirectory == true ? nil : try Data(contentsOf: url),
        modified: values.contentModificationDate)
    }
    return items
  }

  @MainActor func pane(_ id: String, _ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["pane.\(id)"].outlines["fileList"]
  }

  @MainActor func launch(in folder: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = url(folder).path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launch()
    return app
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}
