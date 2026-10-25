import XCTest

final class MetadataPreviewUITests: XCTestCase {
  @MainActor func testPreviewGetInfoAndUnsavedEditRecovery() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("abc".utf8).write(to: root.appendingPathComponent("sample.txt"))
    defer { try? FileManager.default.removeItem(at: root) }
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = root.path
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = "com.fileterm.m05.\(UUID().uuidString)"
    app.launch()
    defer { app.terminate() }
    let file = app.staticTexts["sample.txt"]
    XCTAssertTrue(file.waitForExistence(timeout: 10))
    app.buttons["view.preview"].click()
    app.outlines["fileList"].staticTexts["sample.txt"].click()
    let editor = app.textViews["preview.text"]
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    editor.click()
    editor.typeText(" edited")
    app.buttons["view.preview"].click()
    let recovery = app.windows["Unsaved Edits — sample.txt"]
    XCTAssertTrue(recovery.waitForExistence(timeout: 5))
    recovery.buttons["preview.save"].click()
    XCTAssertTrue(
      try String(contentsOf: root.appendingPathComponent("sample.txt"), encoding: .utf8).contains(
        "edited"))
    recovery.buttons["_XCUI:CloseWindow"].click()
    app.outlines["fileList"].staticTexts["sample.txt"].click()
    app.typeKey("i", modifierFlags: .command)
    XCTAssertTrue(
      app.windows.matching(NSPredicate(format: "title CONTAINS 'Info'")).firstMatch
        .waitForExistence(timeout: 5))
  }
}
