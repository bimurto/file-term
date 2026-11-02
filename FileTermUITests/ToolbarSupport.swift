import XCTest

extension XCUIElement {
  /// A toolbar command button. At the default window width the toolbar's later items move into
  /// its overflow menu, so the window zooms to fit them when the button isn't shown.
  @MainActor func toolbarButton(_ id: String) -> XCUIElement {
    let button = buttons[id].firstMatch
    if !button.waitForExistence(timeout: 2) {
      let app = XCUIApplication()
      app.menuBars.menuBarItems["Window"].click()
      app.menuItems["Zoom"].click()
    }
    return button
  }
}
