import XCTest

final class BrowserSmokeTests: XCTestCase {
  @MainActor func testBrowsePanelsAndSettings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Child"), withIntermediateDirectories: true)
    try Data("sample".utf8).write(to: root.appendingPathComponent("sample.txt"))
    defer { try? FileManager.default.removeItem(at: root) }
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = "com.fileterm.uitests.\(UUID().uuidString)"
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.staticTexts["sample.txt"].waitForExistence(timeout: 10))
    app.staticTexts["Child"].doubleClick()
    XCTAssertTrue(app.staticTexts["This folder is empty"].waitForExistence(timeout: 5))
    for panel in ["Preview", "Activities", "Logs"] {
      app.buttons["view.\(panel.lowercased())"].click()
      XCTAssertTrue(
        app.staticTexts["\(panel) is not implemented yet."].waitForExistence(timeout: 5))
    }
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(
      app.checkBoxes["Restore windows and tabs on startup"].waitForExistence(timeout: 5))
  }
}
