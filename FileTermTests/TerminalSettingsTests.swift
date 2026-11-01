import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct TerminalSettingsTests {
  @Test func terminalDefaultsAndToolbar() {
    let preferences = TerminalPreferences()
    #expect(preferences.shellPath == (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"))
    #expect(preferences.loginShell)
    #expect(preferences.interactiveShell)
    #expect(preferences.integrationEnabled)
    #expect(preferences.reverseSync)
    #expect(preferences.followMode == .active)
    #expect(preferences.fontSize == 13)
    #expect(preferences.cursorStyle == .block)
    #expect(preferences.scrollbackLines == 10_000)
    #expect(WorkspacePreferences().toolbarItems.contains("view.terminal"))
    #expect(ToolbarSymbols.symbol(for: "view.terminal") == "terminal")
    #expect(SettingsCategory.terminal.symbol == "terminal")
  }

  @Test func terminalPreferencesRoundTripThroughDefaults() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    settings.terminal.shellPath = "/bin/bash"
    settings.terminal.loginShell = false
    settings.terminal.interactiveShell = false
    settings.terminal.integrationEnabled = false
    settings.terminal.reverseSync = false
    settings.terminal.followMode = .second
    settings.terminal.fontName = "Menlo"
    settings.terminal.fontSize = 16
    settings.terminal.cursorStyle = .bar
    settings.terminal.scrollbackLines = 5_000
    settings.terminal.themeID = "dracula"
    #expect(AppSettings(suite: suite).terminal == settings.terminal)
    let data = try JSONEncoder().encode(settings.terminal)
    #expect(try JSONDecoder().decode(TerminalPreferences.self, from: data) == settings.terminal)
  }

  @Test func preferencesSavedBeforeColorThemesKeepTheirValues() throws {
    let saved = Data(
      """
      {"shellPath":"/bin/bash","loginShell":false,"interactiveShell":true,
       "integrationEnabled":true,"reverseSync":true,"followMode":"active","fontName":"Menlo",
       "fontSize":16,"cursorStyle":"bar","scrollbackLines":5000}
      """.utf8)
    let preferences = try JSONDecoder().decode(TerminalPreferences.self, from: saved)
    #expect(preferences.shellPath == "/bin/bash")
    #expect(preferences.fontSize == 16)
    #expect(preferences.themeID == nil)
  }

  @Test func theShippedThemesLoadWithoutJoiningTheAppThemes() {
    #expect(
      ThemeLibrary.terminalThemes.map(\.id) == [
        "dracula", "nord", "solarized-dark", "solarized-light", "gruvbox-dark",
        "github-light-default",
      ])
    #expect(ThemeLibrary.themes.count == 9)
  }

  @Test func importingATwiceReplacesItAndRemovingFallsBackToSystem() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    let colors = Array(repeating: "#112233", count: 16)
    func theme(background: String) -> TerminalTheme {
      TerminalTheme(
        id: "imported.Mine", name: "Mine", foreground: "#FFFFFF", background: background,
        cursor: "#FFFFFF", selection: "#333333", ansi: colors)
    }

    settings.terminal.importTheme(theme(background: "#000000"))
    settings.terminal.importTheme(theme(background: "#222222"))
    #expect(settings.terminal.importedThemes?.count == 1)
    #expect(settings.terminal.themeID == "imported.Mine")
    #expect(settings.terminal.colorThemes.last?.background == "#222222")
    #expect(AppSettings(suite: suite).terminal == settings.terminal)

    settings.terminal.removeImportedTheme(id: "imported.Mine")
    #expect(settings.terminal.importedThemes?.isEmpty == true)
    #expect(settings.terminal.themeID == nil)
  }

  @Test func panelDefaultsAndWindowSnapshotCompatibility() throws {
    let panel = TerminalPanelState()
    #expect(!panel.isVisible)
    #expect(panel.dock == .bottom)
    #expect(panel.size == 220)
    let browserJSON = """
      {"first":[],"second":[],"firstSelected":0,"secondSelected":0,
       "layout":"single","lastDualLayout":"vertical","activePane":"first"}
      """
    let oldJSON = Data("{\"browser\":\(browserJSON),\"frame\":\"old frame\"}".utf8)
    let old = try JSONDecoder().decode(WindowSnapshot.self, from: oldJSON)
    #expect(old.terminal == nil)
    let state = TerminalPanelState(isVisible: true, dock: .right, size: 320)
    let snapshot = WindowSnapshot(browser: old.browser, frame: old.frame, terminal: state)
    let encoded = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(WindowSnapshot.self, from: encoded).terminal == state)
    #expect(WindowSnapshot(browser: old.browser, frame: old.frame).terminal == nil)
  }
}
