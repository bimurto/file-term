import AppKit
import XCTest

final class AdditionalCapabilitiesUITests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    continueAfterFailure = false
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("FileTermM13-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("reveal-target.txt"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  // Leaves the window on the test folder so reveal requests need no Home listing.
  @MainActor private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = "com.fileterm.uitests.\(UUID().uuidString)"
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = folder.path
    app.launch()
    XCTAssertTrue(app.windows["browserWindow"].waitForExistence(timeout: 10))
    return app
  }

  @MainActor func testSavedWorkspaceAppearsInTheSidebarAndLoadsInPlaceOfOpenWindows() {
    let app = launch()
    defer { app.terminate() }
    app.menuBars.menuBarItems["Go"].click()
    app.menuBars.menuItems["Workspaces"].click()
    app.menuBars.menuItems["Save Workspace…"].click()
    let dialog = app.dialogs.firstMatch
    let field = dialog.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.click()
    field.typeText("M13 Layout")
    dialog.buttons["Save"].click()

    let row = app.descendants(matching: .any)["workspace.M13 Layout"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    row.click()
    let onlyOneWindow = NSPredicate { _, _ in
      app.windows.matching(identifier: "browserWindow").count == 1
    }
    expectation(for: onlyOneWindow, evaluatedWith: nil)
    waitForExpectations(timeout: 10)
  }

  @MainActor func testRevealRequestOpensTheEnclosingFolderAndSelectsTheFile() throws {
    let app = launch()
    defer { app.terminate() }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.fileterm.app")
    let appURL = try XCTUnwrap(running.last?.bundleURL)
    NSWorkspace.shared.open(
      [folder.appendingPathComponent("reveal-target.txt")], withApplicationAt: appURL,
      configuration: NSWorkspace.OpenConfiguration())
    let list = app.outlines["fileList"]
    XCTAssertTrue(list.staticTexts["reveal-target.txt"].waitForExistence(timeout: 10))
    let row = list.outlineRows.containing(.staticText, identifier: "reveal-target.txt").firstMatch
    XCTAssertTrue(row.isSelected)
  }

  @MainActor func testIntegrationsSettingsExplainTheDefaultViewerAndDialogs() {
    let app = launch()
    defer { app.terminate() }
    app.typeKey(",", modifierFlags: .command)
    let tab = app.buttons["settingsTab.Integrations"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    let toggle = app.descendants(matching: .any)["defaultFileViewer"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["dropboxToken"].exists)
    let note = NSPredicate(format: "value CONTAINS 'Open and Save'")
    XCTAssertTrue(app.staticTexts.matching(note).firstMatch.exists)
  }
}
