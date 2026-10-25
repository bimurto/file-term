import XCTest

final class TerminalUITests: XCTestCase {
  @MainActor func testTerminalToggleAndEscapeRouting() throws {
    let app = XCUIApplication()
    let suite = "FileTerm.TerminalUITests.\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: folder.appendingPathComponent("terminal-fixture.txt"))
    defer { try? FileManager.default.removeItem(at: folder) }
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = folder.path
    app.launch()
    defer {
      app.terminate()
      UserDefaults.standard.removePersistentDomain(forName: suite)
    }
    XCTAssertTrue(
      app.outlines["fileList"].staticTexts["terminal-fixture.txt"].waitForExistence(timeout: 15))
    let toggle = app.buttons["view.terminal"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    app.menuBars.menuBarItems["View"].click()
    app.menuItems["Show Terminal"].click()
    let panel = app.buttons["terminalClose"]
    XCTAssertTrue(panel.waitForExistence(timeout: 10), app.debugDescription)
    app.typeKey("`", modifierFlags: [.control, .option])
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertEqual(app.sheets.count, 0, "Escape in the terminal must not open Quick Open")
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "M06 terminal drawer"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.typeKey("`", modifierFlags: [.control])
    XCTAssertFalse(panel.exists)
    app.typeKey("`", modifierFlags: [.control])
    XCTAssertTrue(panel.waitForExistence(timeout: 5))
  }
}
