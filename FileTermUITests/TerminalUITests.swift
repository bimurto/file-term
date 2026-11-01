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

  @MainActor func testColorThemeAppliesToAnOpenTerminalAndPersists() throws {
    let app = XCUIApplication()
    let suite = "FileTerm.TerminalUITests.\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: folder.appendingPathComponent("terminal-fixture.txt"))
    let colors = """
      for i in 0 1 2 3 4 5 6 7; do
        printf '\\033[3%sm#%s \\033[9%sm#%s ' $i $i $i $i
      done
      printf '\\033[0m\\n'

      """
    try Data(colors.utf8).write(to: folder.appendingPathComponent("colors.sh"))
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
    showTerminal(app)
    app.typeKey("`", modifierFlags: [.control, .option])
    app.typeText("sh colors.sh\n")
    sleep(1)
    capture(app, "terminal system colors")

    chooseColorTheme("Dracula", app)
    capture(app, "terminal dracula")
    assertPanelBackground(app, red: 0x28, green: 0x2A, blue: 0x36)

    // A light app must not pull a dark terminal theme back to the system colors.
    app.typeKey(",", modifierFlags: .command)
    app.buttons["settingsTab.Themes"].click()
    app.staticTexts["theme.light"].click()
    app.typeKey("w", modifierFlags: .command)
    sleep(1)
    capture(app, "terminal dracula in light app")
    assertPanelBackground(app, red: 0x28, green: 0x2A, blue: 0x36)

    chooseColorTheme("Solarized Light", app)
    capture(app, "terminal solarized light")
    assertPanelBackground(app, red: 0xFD, green: 0xF6, blue: 0xE3)

    app.terminate()
    app.launch()
    XCTAssertTrue(
      app.outlines["fileList"].staticTexts["terminal-fixture.txt"].waitForExistence(timeout: 15))
    showTerminal(app)
    sleep(1)
    capture(app, "terminal solarized light after relaunch")
    assertPanelBackground(app, red: 0xFD, green: 0xF6, blue: 0xE3)

    chooseColorTheme("System", app)
    capture(app, "terminal system colors again")
    assertPanelBackground(app, red: 0xFF, green: 0xFF, blue: 0xFF)

    app.typeKey("`", modifierFlags: [.control, .option])
    app.typeText("sh colors.sh\n")
    chooseColorTheme("GitHub Light Default", app)
    capture(app, "terminal github light default")
    chooseColorTheme("Dracula", app)
    app.typeKey("a", modifierFlags: .command)
    sleep(1)
    capture(app, "terminal dracula selection")
    chooseColorTheme("GitHub Light Default", app)
    capture(app, "terminal github light default selection")
  }

  @MainActor func testImportingAnITermColorSchemeAppliesAndPersists() throws {
    let app = XCUIApplication()
    let suite = "FileTerm.TerminalUITests.\(UUID().uuidString)"
    // No digits in this path: it's typed into the file panel, and typed digits can get lost.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImportFixture")
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: folder.appendingPathComponent("terminal-fixture.txt"))
    defer { try? FileManager.default.removeItem(at: folder) }

    func color(_ red: Int, _ green: Int, _ blue: Int) -> [String: Any] {
      [
        "Red Component": Double(red) / 255, "Green Component": Double(green) / 255,
        "Blue Component": Double(blue) / 255, "Color Space": "sRGB",
      ]
    }
    var scheme: [String: Any] = [
      "Foreground Color": color(0xFF, 0xFF, 0xFF), "Background Color": color(0x12, 0x34, 0x56),
    ]
    for index in 0..<16 { scheme["Ansi \(index) Color"] = color(0xFF, index * 16, 0x40) }
    let file = folder.appendingPathComponent("Imported Sample.itermcolors")
    try PropertyListSerialization.data(fromPropertyList: scheme, format: .xml, options: 0)
      .write(to: file)

    app.launchEnvironment["FILETERM_SETTINGS_SUITE"] = suite
    app.launchEnvironment["FILETERM_INITIAL_DIRECTORY"] = folder.path
    app.launch()
    defer {
      app.terminate()
      UserDefaults.standard.removePersistentDomain(forName: suite)
    }
    XCTAssertTrue(
      app.outlines["fileList"].staticTexts["terminal-fixture.txt"].waitForExistence(timeout: 15))
    showTerminal(app)

    app.typeKey(",", modifierFlags: .command)
    let tab = app.buttons["settingsTab.Terminal"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    let importButton = app.buttons["terminalImportColorScheme"]
    XCTAssertTrue(importButton.waitForExistence(timeout: 5))
    importButton.click()

    sleep(1)
    app.typeKey("g", modifierFlags: [.command, .shift])
    sleep(1)
    app.typeText(file.path)
    sleep(1)
    app.typeKey(.return, modifierFlags: [])
    sleep(1)
    app.typeKey(.return, modifierFlags: [])

    let remove = app.buttons["terminalRemoveColorScheme"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    capture(app, "terminal import settings")
    app.typeKey("w", modifierFlags: .command)
    sleep(1)
    capture(app, "terminal imported scheme")
    assertPanelBackground(app, red: 0x12, green: 0x34, blue: 0x56)

    app.terminate()
    app.launch()
    XCTAssertTrue(
      app.outlines["fileList"].staticTexts["terminal-fixture.txt"].waitForExistence(timeout: 15))
    showTerminal(app)
    sleep(1)
    assertPanelBackground(app, red: 0x12, green: 0x34, blue: 0x56)

    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    remove.click()
    XCTAssertFalse(remove.waitForExistence(timeout: 1))
    XCTAssertEqual(app.popUpButtons["terminalColorTheme"].value as? String, "System")
  }

  @MainActor private func showTerminal(_ app: XCUIApplication) {
    guard !app.buttons["terminalClose"].exists else { return }
    app.menuBars.menuBarItems["View"].click()
    app.menuItems["Show Terminal"].click()
    XCTAssertTrue(app.buttons["terminalClose"].waitForExistence(timeout: 10))
  }

  @MainActor private func chooseColorTheme(_ name: String, _ app: XCUIApplication) {
    app.typeKey(",", modifierFlags: .command)
    let tab = app.buttons["settingsTab.Terminal"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.click()
    let picker = app.popUpButtons["terminalColorTheme"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    picker.click()
    app.menuItems[name].click()
    app.typeKey("w", modifierFlags: .command)
    // Changes reach open terminals after a short debounce.
    sleep(1)
  }

  /// Samples the empty area below the prompt, away from the window's rounded corner.
  @MainActor private func assertPanelBackground(
    _ app: XCUIApplication, red: Int, green: Int, blue: Int,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let panel = app.descendants(matching: .any)["terminalPanel"]
    let image = panel.screenshot().image
    guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
      return XCTFail("No panel screenshot", file: file, line: line)
    }
    // Raw samples in the display's color space, which is why the comparison isn't exact:
    // on Display P3, #123456 reads as (27, 51, 83).
    var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
    bitmap.getPixel(&pixel, atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 40)
    for (actual, expected) in zip(pixel, [red, green, blue]) {
      XCTAssertEqual(actual, expected, accuracy: 10, file: file, line: line)
    }
  }

  @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
