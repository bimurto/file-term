import XCTest

final class NavigationUITests: XCTestCase {
  @MainActor func testHistoryAndGoToFolderValidation() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    app.buttons["go.enclosingFolder"].click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["Right"].waitForExistence(
        timeout: 5))
    app.buttons["go.back"].click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["left.txt"].waitForExistence(
        timeout: 5))
    app.buttons["go.forward"].click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["Right"].waitForExistence(
        timeout: 5))
    app.buttons["go.back"].click()
    app.buttons["go.toFolder"].click()
    let field = app.textFields["goToFolderPath"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("relative")
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.staticTexts["goToFolderError"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.outlines.matching(identifier: "fileList").staticTexts["left.txt"].exists)
    field.typeKey("a", modifierFlags: .command)
    field.typeText(fixture.right.path)
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["right.txt"].waitForExistence(
        timeout: 5))
    app.menuBars.menuBarItems["Go"].click()
    app.menuItems["Recent Folders"].hover()
    XCTAssertTrue(app.menuItems[fixture.left.path].waitForExistence(timeout: 5))
    app.typeKey(.escape, modifierFlags: [])
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testDualPanesCloneSwapSyncAndSingleActivePane() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["left.txt"].waitForExistence(
        timeout: 10))
    app.buttons["view.vertical"].click()
    XCTAssertEqual(app.outlines.matching(identifier: "fileList").count, 2)
    let tables = app.outlines.matching(identifier: "fileList")
    tables.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).click()
    openFolder(fixture.right.path, app: app)
    XCTAssertTrue(tables.element(boundBy: 1).staticTexts["right.txt"].waitForExistence(timeout: 5))
    app.buttons["view.single"].click()
    XCTAssertEqual(tables.count, 1)
    XCTAssertTrue(app.outlines.matching(identifier: "fileList").staticTexts["right.txt"].exists)
    app.buttons["view.horizontal"].click()
    XCTAssertEqual(tables.count, 2)
    tables.element(boundBy: 0).staticTexts["left.txt"].click()
    app.buttons["go.syncBrowsing"].click()
    tables.element(boundBy: 1).staticTexts["Shared"].doubleClick()
    XCTAssertTrue(
      tables.element(boundBy: 0).staticTexts["left-child.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      tables.element(boundBy: 1).staticTexts["right-child.txt"].waitForExistence(timeout: 5))
    app.buttons["view.single"].click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["right-child.txt"].waitForExistence(
        timeout: 5))
    app.buttons["view.horizontal"].click()
    app.buttons["go.syncBrowsing"].click()
    app.buttons["go.enclosingFolder"].click()
    XCTAssertTrue(tables.element(boundBy: 0).staticTexts["left.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(tables.element(boundBy: 1).staticTexts["right.txt"].waitForExistence(timeout: 5))
    menu("View", command: "Swap Panes", app: app)
    XCTAssertTrue(tables.element(boundBy: 0).staticTexts["right.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(tables.element(boundBy: 1).staticTexts["left.txt"].waitForExistence(timeout: 5))
    menu("View", command: "Clone Pane", app: app)
    XCTAssertTrue(tables.element(boundBy: 0).staticTexts["left.txt"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "M01 horizontal panes"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor func testMinimumWindowLayoutsAndBreadcrumbs() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    let path = app.descendants(matching: .any)["currentPath"]
    let ancestor = path.staticTexts.matching(
      NSPredicate(format: "value BEGINSWITH %@", String(fixture.root.lastPathComponent.prefix(8)))
    ).firstMatch
    XCTAssertTrue(ancestor.exists)
    ancestor.click()
    XCTAssertTrue(app.outlines["fileList"].staticTexts["Right"].waitForExistence(timeout: 5))
    let window = app.windows["browserWindow"]
    let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(
      CGVector(dx: -2, dy: -2))
    let destination = window.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: 678, dy: 450))
    corner.press(forDuration: 0.1, thenDragTo: destination)
    for layout in ["view.vertical", "view.horizontal"] {
      app.buttons[layout].click()
      XCTAssertEqual(app.outlines.matching(identifier: "fileList").count, 2)
      XCTAssertTrue(app.buttons["go.toFolder"].isHittable)
      for index in 0..<2 {
        XCTAssertGreaterThanOrEqual(
          app.outlines.matching(identifier: "fileList").element(boundBy: index).frame.width, 218)
      }
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "M01 minimum window \(layout)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    openFolder("/", app: app)
    XCTAssertFalse(app.buttons["go.enclosingFolder"].isEnabled)
  }

  @MainActor func testVisibilityTogglesAndSelectedSize() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["left.txt"].waitForExistence(
        timeout: 10))
    app.outlines.matching(identifier: "fileList").staticTexts["left.txt"].click()
    XCTAssertTrue(app.staticTexts["selectedSize"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      (app.staticTexts["selectedSize"].value as? String ?? app.staticTexts["selectedSize"].label)
        .contains("4 bytes"))
    menu("View", command: "Show Path Bar", app: app)
    XCTAssertFalse(app.descendants(matching: .any)["currentPath"].exists)
    menu("View", command: "Show Path Bar", app: app)
    XCTAssertTrue(app.descendants(matching: .any)["currentPath"].exists)
    menu("View", command: "Show Toolbar", app: app)
    XCTAssertFalse(app.buttons["go.toFolder"].exists)
    menu("View", command: "Show Toolbar", app: app)
    XCTAssertTrue(app.buttons["go.toFolder"].exists)
    menu("View", command: "Show Title Bar", app: app)
    XCTAssertTrue(app.windows.buttons[XCUIIdentifierCloseWindow].exists)
    menu("View", command: "Show Title Bar", app: app)
  }

  @MainActor private func openFolder(_ path: String, app: XCUIApplication) {
    app.buttons["go.toFolder"].click()
    let field = app.textFields["goToFolderPath"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(path)
    field.typeKey(.return, modifierFlags: [])
  }

  @MainActor private func menu(_ title: String, command: String, app: XCUIApplication) {
    app.menuBars.menuBarItems[title].click()
    app.menuItems[command].click()
  }
}

private struct Fixture {
  let root: URL
  let left: URL
  let right: URL
  let suite = "com.fileterm.uitests.\(UUID().uuidString)"

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    left = root.appendingPathComponent("Left")
    right = root.appendingPathComponent("Right")
    for directory in [left, right] {
      try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("Shared"), withIntermediateDirectories: true)
    }
    try Data("left".utf8).write(to: left.appendingPathComponent("left.txt"))
    try Data("right".utf8).write(to: right.appendingPathComponent("right.txt"))
    try Data().write(to: left.appendingPathComponent("Shared/left-child.txt"))
    try Data().write(to: right.appendingPathComponent("Shared/right-child.txt"))
  }

  @MainActor func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = left.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launch()
    return app
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}
