import XCTest

final class NavigationUITests: XCTestCase {
  @MainActor func testConnectToolbarButtonOpensTheConnectionForm() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    app.buttons["go.connect"].click()
    XCTAssertTrue(app.popUpButtons["connectionProtocol"].waitForExistence(timeout: 5))
  }

  @MainActor func testDraggingAFolderOntoTheSidebarAddsAFavorite() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    XCTAssertTrue(hint.waitForExistence(timeout: 5))
    app.buttons["go.enclosingFolder"].click()
    let list = app.outlines.matching(identifier: "fileList")
    let folder = list.staticTexts["Right"]
    XCTAssertTrue(folder.waitForExistence(timeout: 5))
    folder.press(forDuration: 0.5, thenDragTo: hint)
    XCTAssertTrue(
      app.descendants(matching: .any)["sidebarFavorite.Right"].waitForExistence(timeout: 5))
    XCTAssertFalse(hint.exists)
  }

  @MainActor func testSidebarSectionsFoldFromTheirHeaders() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    let tag = app.descendants(matching: .any)["sidebarTag.Gray"]
    XCTAssertTrue(tag.waitForExistence(timeout: 5))
    let header = app.descendants(matching: .any)["sidebarHeader.tags"]
    header.click()
    let hidden = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: tag)
    wait(for: [hidden], timeout: 5)
    header.click()
    XCTAssertTrue(tag.waitForExistence(timeout: 5))
  }

  @MainActor func testSidebarDragsWiderThanTheOldLimitAndKeepsThePaneUsable() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    let sidebar = app.descendants(matching: .any)["navigationSidebar"]
    XCTAssertLessThan(sidebar.frame.width, 200, "The sidebar starts at its default width")
    let handle = app.descendants(matching: .any)["sidebarResizeHandle"]
    XCTAssertTrue(handle.exists)
    let center = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 200, dy: 0)))
    XCTAssertGreaterThan(sidebar.frame.width, 300)
    let further = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    further.press(forDuration: 0.1, thenDragTo: further.withOffset(CGVector(dx: 2000, dy: 0)))
    let list = app.outlines.matching(identifier: "fileList").firstMatch
    XCTAssertGreaterThanOrEqual(list.frame.width, 218)
  }

  @MainActor func testDraggingAFileOntoTheSidebarAddsNothing() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    let file = app.outlines.matching(identifier: "fileList").staticTexts["left.txt"]
    XCTAssertTrue(file.waitForExistence(timeout: 10))
    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    XCTAssertTrue(hint.waitForExistence(timeout: 5))
    file.press(forDuration: 0.5, thenDragTo: hint)
    sleep(2)
    XCTAssertFalse(app.descendants(matching: .any)["sidebarFavorite.left.txt"].exists)
    XCTAssertTrue(hint.exists)
  }

  @MainActor func testNewWindowWorksAfterTheLastWindowCloses() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    let window = app.windows["browserWindow"]
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    app.typeKey("w", modifierFlags: [.command, .shift])
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: window)
    wait(for: [gone], timeout: 5)
    app.menuBars.menuBarItems["File"].click()
    app.menuItems["New FileTerm Window"].click()
    XCTAssertTrue(window.waitForExistence(timeout: 5))
  }

  /// Fills the connection form for a service in dev/docker-compose.yml.
  @MainActor private func fillLiveForm(
    _ app: XCUIApplication, protocolName: String = "WebDAV", server: String = "127.0.0.1",
    defaultPort: String = "80", port serverPort: String = "8080"
  ) {
    app.buttons["go.connect"].click()
    let kind = app.popUpButtons["connectionProtocol"]
    XCTAssertTrue(kind.waitForExistence(timeout: 5))
    kind.click()
    app.menuItems[protocolName].click()
    let sheet = app.sheets.firstMatch
    sheet.textFields["connectionServer"].click()
    sheet.textFields["connectionServer"].typeText(server)
    sheet.textFields["connectionUsername"].click()
    sheet.textFields["connectionUsername"].typeText("tester")
    sheet.secureTextFields["connectionPassword"].click()
    sheet.secureTextFields["connectionPassword"].typeText("testpass123")
    let advanced = sheet.disclosureTriangles["connectionAdvanced"]
    // Only the arrow toggles the group, not its label.
    advanced.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).click()
    // The group's identifier replaces its fields' own, so this one is found by its placeholder.
    let port = sheet.textFields.matching(
      NSPredicate(format: "placeholderValue == %@", defaultPort)
    ).firstMatch
    XCTAssertTrue(port.waitForExistence(timeout: 5))
    port.click()
    port.typeText(serverPort + "\t")
  }

  /// Run with `TEST_RUNNER_FILETERM_LIVE=1` and the `webdav` service, holding a folder named
  /// `m16-folder` with `inside.md` and a file named `m16-file.md`. Stores a keychain item.
  @MainActor func testLiveSavedConnectionOpensAndAFolderBecomesAFavoriteThatReopens() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1")
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    fillLiveForm(app)
    app.sheets.firstMatch.buttons["connectionSave"].click()

    app.menuBars.menuBarItems["Go"].click()
    app.menuItems["Connections"].hover()
    let saved = app.menuItems["127.0.0.1:8080"]
    XCTAssertTrue(saved.waitForExistence(timeout: 5))
    saved.click()
    let folder = app.outlines.matching(identifier: "fileList").staticTexts["m16-folder"].firstMatch
    XCTAssertTrue(folder.waitForExistence(timeout: 15))

    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    let file = app.outlines.matching(identifier: "fileList").staticTexts["m16-file.md"].firstMatch
    file.press(forDuration: 0.5, thenDragTo: hint)
    sleep(2)
    XCTAssertFalse(app.descendants(matching: .any)["sidebarFavorite.m16-file.md"].exists)
    folder.press(forDuration: 0.5, thenDragTo: hint)
    let favorite = app.descendants(matching: .any)["sidebarFavorite.m16-folder"]
    XCTAssertTrue(favorite.waitForExistence(timeout: 5))

    // A relaunch has no open connection, so the favorite must connect again to reopen.
    app.terminate()
    app.launch()
    let reopened = app.descendants(matching: .any)["sidebarFavorite.m16-folder"]
    XCTAssertTrue(reopened.waitForExistence(timeout: 10))
    reopened.click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["inside.md"].firstMatch
        .waitForExistence(timeout: 15))
  }

  /// Run as above. Connects without saving, so nothing reaches the keychain.
  @MainActor func testLiveFolderFromAnUnsavedConnectionIsRefusedWithANotice() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1")
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    fillLiveForm(app)
    app.sheets.firstMatch.buttons["connectionConnect"].click()
    let folder = app.outlines.matching(identifier: "fileList").staticTexts["m16-folder"].firstMatch
    XCTAssertTrue(folder.waitForExistence(timeout: 15))
    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    folder.press(forDuration: 0.5, thenDragTo: hint)
    XCTAssertTrue(app.descendants(matching: .any)["browserNotice"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["sidebarFavorite.m16-folder"].exists)
    XCTAssertTrue(hint.exists)
  }

  /// A recreated `sftp` container has new host keys, and FileTerm rightly refuses them if it
  /// trusted the old ones under that address. Set `TEST_RUNNER_FILETERM_SFTP_HOST` to another
  /// address of this Mac to test without removing them. `localhost` and `127.1` don't work here:
  /// `ssh-keyscan` tries IPv6 for the first, and ssh turns the second into `127.0.0.1`.
  private var liveSFTPHost: String {
    ProcessInfo.processInfo.environment["FILETERM_SFTP_HOST"] ?? "127.0.0.1"
  }

  @MainActor private func fillLiveSFTPForm(_ app: XCUIApplication) {
    fillLiveForm(
      app, protocolName: "SFTP", server: liveSFTPHost, defaultPort: "22", port: "2222")
  }

  /// Accepts the host key question, which appears only the first time FileTerm sees the server.
  @MainActor private func trustServerIfAsked(_ app: XCUIApplication) {
    // One alert, but accessibility lists its button twice.
    let trust = app.buttons.matching(identifier: "Trust").firstMatch
    if trust.waitForExistence(timeout: 5) { trust.click() }
  }

  /// Opens the `upload` folder, the only writable place on the `sftp` service.
  @MainActor private func openLiveSFTPUploadFolder(_ app: XCUIApplication) {
    let upload = app.outlines.matching(identifier: "fileList").staticTexts["upload"].firstMatch
    XCTAssertTrue(upload.waitForExistence(timeout: 20))
    upload.doubleClick()
  }

  /// Run with `TEST_RUNNER_FILETERM_LIVE=1` and the `sftp` service, with `m16-folder/inside.md` and
  /// `m16-file.md` in its `upload` folder. Stores a keychain item.
  @MainActor func testLiveSFTPSavedConnectionOpensAndAFolderBecomesAFavoriteThatReopens() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1")
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    fillLiveSFTPForm(app)
    app.sheets.firstMatch.buttons["connectionSave"].click()

    app.menuBars.menuBarItems["Go"].click()
    app.menuItems["Connections"].hover()
    let saved = app.menuItems["\(liveSFTPHost):2222"]
    XCTAssertTrue(saved.waitForExistence(timeout: 5))
    saved.click()
    trustServerIfAsked(app)
    openLiveSFTPUploadFolder(app)
    let list = app.outlines.matching(identifier: "fileList")
    let folder = list.staticTexts["m16-folder"].firstMatch
    XCTAssertTrue(folder.waitForExistence(timeout: 15))

    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    list.staticTexts["m16-file.md"].firstMatch.press(forDuration: 0.5, thenDragTo: hint)
    sleep(2)
    XCTAssertFalse(app.descendants(matching: .any)["sidebarFavorite.m16-file.md"].exists)
    folder.press(forDuration: 0.5, thenDragTo: hint)
    let favorite = app.descendants(matching: .any)["sidebarFavorite.m16-folder"]
    XCTAssertTrue(favorite.waitForExistence(timeout: 5))

    // A relaunch has no open connection, so the favorite must connect again to reopen.
    app.terminate()
    app.launch()
    let reopened = app.descendants(matching: .any)["sidebarFavorite.m16-folder"]
    XCTAssertTrue(reopened.waitForExistence(timeout: 10))
    reopened.click()
    XCTAssertTrue(list.staticTexts["inside.md"].firstMatch.waitForExistence(timeout: 20))
  }

  /// Run as above. Connects without saving, so nothing reaches the keychain.
  @MainActor func testLiveSFTPFolderFromAnUnsavedConnectionIsRefusedWithANotice() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1")
    let fixture = try Fixture()
    defer { fixture.remove() }
    let app = fixture.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["left.txt"].waitForExistence(timeout: 10))
    fillLiveSFTPForm(app)
    app.sheets.firstMatch.buttons["connectionConnect"].click()
    trustServerIfAsked(app)
    openLiveSFTPUploadFolder(app)
    let folder = app.outlines.matching(identifier: "fileList").staticTexts["m16-folder"].firstMatch
    XCTAssertTrue(folder.waitForExistence(timeout: 15))
    let hint = app.descendants(matching: .any)["favoritesDropHint"]
    folder.press(forDuration: 0.5, thenDragTo: hint)
    XCTAssertTrue(app.descendants(matching: .any)["browserNotice"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["sidebarFavorite.m16-folder"].exists)
    XCTAssertTrue(hint.exists)
  }

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
    app.toolbarButton("go.toFolder").click()
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
    app.radioButtons["Vertical — Side by Side"].click()
    XCTAssertEqual(app.outlines.matching(identifier: "fileList").count, 2)
    let tables = app.outlines.matching(identifier: "fileList")
    tables.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).click()
    openFolder(fixture.right.path, app: app)
    XCTAssertTrue(tables.element(boundBy: 1).staticTexts["right.txt"].waitForExistence(timeout: 5))
    app.radioButtons["Single Pane"].click()
    XCTAssertEqual(tables.count, 1)
    XCTAssertTrue(app.outlines.matching(identifier: "fileList").staticTexts["right.txt"].exists)
    app.radioButtons["Horizontal — Stacked"].click()
    XCTAssertEqual(tables.count, 2)
    tables.element(boundBy: 0).staticTexts["left.txt"].click()
    app.buttons["go.syncBrowsing"].click()
    tables.element(boundBy: 1).staticTexts["Shared"].doubleClick()
    XCTAssertTrue(
      tables.element(boundBy: 0).staticTexts["left-child.txt"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      tables.element(boundBy: 1).staticTexts["right-child.txt"].waitForExistence(timeout: 5))
    app.radioButtons["Single Pane"].click()
    XCTAssertTrue(
      app.outlines.matching(identifier: "fileList").staticTexts["right-child.txt"].waitForExistence(
        timeout: 5))
    app.radioButtons["Horizontal — Stacked"].click()
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
    // At the minimum width the toolbar may overflow, so the layouts come from the View menu.
    for layout in ["Vertical — Side by Side", "Horizontal — Stacked"] {
      menu("View", command: layout, app: app)
      XCTAssertEqual(app.outlines.matching(identifier: "fileList").count, 2)
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
    XCTAssertFalse(app.buttons["go.back"].exists)
    menu("View", command: "Show Toolbar", app: app)
    XCTAssertTrue(app.buttons["go.back"].waitForExistence(timeout: 5))
    menu("View", command: "Show Title Bar", app: app)
    XCTAssertTrue(app.windows.buttons[XCUIIdentifierCloseWindow].exists)
    menu("View", command: "Show Title Bar", app: app)
  }

  @MainActor private func openFolder(_ path: String, app: XCUIApplication) {
    app.toolbarButton("go.toFolder").click()
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
