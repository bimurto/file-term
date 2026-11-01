import AppKit
import FileTermCore
import SwiftTerm
import Testing

@testable import FileTerm

@MainActor struct TerminalAppearanceTests {
  @Test func appearanceUpdatesTheRetainedViewWithoutResettingItsContents() {
    let session = makeClosedSession()
    let view = session.terminalView
    let terminal = view.getTerminal()
    view.feed(text: "retained terminal output")
    var preferences = TerminalPreferences()
    preferences.fontName = "Menlo"
    preferences.fontSize = 18
    preferences.scrollbackLines = 2_000
    preferences.cursorStyle = .bar

    session.applyAppearance(preferences)

    #expect(session.terminalView === view)
    #expect(view.getTerminal() === terminal)
    #expect(view.font == NSFont(name: "Menlo", size: 18))
    #expect(terminal.options.scrollback == 2_000)
    #expect(terminal.options.cursorStyle == .steadyBar)
    #expect(
      terminal.getLine(row: 0)?.translateToString(trimRight: true) == "retained terminal output")
    #expect(session.status == .closed)
  }

  @Test func unavailableFontFallsBackToSystemMonospace() {
    let session = makeClosedSession()
    var preferences = TerminalPreferences()
    preferences.fontName = "FileTerm-Nonexistent-Font-For-Testing"
    preferences.fontSize = 17

    session.applyAppearance(preferences)

    #expect(session.terminalView.font == NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
  }

  @Test(arguments: [-100.0, 8, 24, 48, 1_000, .infinity, -.infinity, .nan])
  func fontSizeIsBounded(size: Double) {
    let session = makeClosedSession()
    var preferences = TerminalPreferences()
    preferences.fontSize = size

    session.applyAppearance(preferences)

    let expected = size.isFinite ? min(48, max(8, size)) : 13
    #expect(session.terminalView.font.pointSize == CGFloat(expected))
  }

  @Test(arguments: [Int.min, -1, 0, 2_000, 100_000, Int.max])
  func scrollbackIsBounded(lines: Int) {
    let session = makeClosedSession()
    var preferences = TerminalPreferences()
    preferences.scrollbackLines = lines

    session.applyAppearance(preferences)

    #expect(session.terminalView.getTerminal().options.scrollback == min(100_000, max(0, lines)))
  }

  @Test func cursorStylesMapToSteadySwiftTermStyles() {
    let session = makeClosedSession()
    var preferences = TerminalPreferences()
    for style in TerminalCursorStyle.allCases {
      preferences.cursorStyle = style
      session.applyAppearance(preferences)
      let actual = session.terminalView.getTerminal().options.cursorStyle
      switch style {
      case .block: #expect(actual == .steadyBlock)
      case .underline: #expect(actual == .steadyUnderline)
      case .bar: #expect(actual == .steadyBar)
      }
    }
  }

  @Test func aColorThemeRecolorsTheRetainedViewAndSurvivesAnAppearanceChange() {
    let session = makeClosedSession()
    let view = session.terminalView
    let terminal = view.getTerminal()
    view.feed(text: "retained terminal output")
    var preferences = TerminalPreferences()
    preferences.themeID = "dracula"

    session.applyAppearance(preferences)
    view.viewDidChangeEffectiveAppearance()

    #expect(view.colorTheme?.id == "dracula")
    #expect(terminal.foregroundColor == Color(red8: 0xF8, green8: 0xF8, blue8: 0xF2))
    #expect(terminal.backgroundColor == Color(red8: 0x28, green8: 0x2A, blue8: 0x36))
    #expect(view.selectedTextBackgroundColor == NSColor(themeHex: "#44475A"))
    #expect(view.selectedTextForegroundColor == NSColor(themeHex: "#F8F8F2"))
    #expect(view.caretColor == NSColor(themeHex: "#F8F8F2"))
    #expect(view.caretTextColor == NSColor(themeHex: "#282A36"))
    #expect(
      terminal.getLine(row: 0)?.translateToString(trimRight: true) == "retained terminal output")
  }

  @Test func returningToSystemRestoresEveryColor() {
    let session = makeClosedSession()
    let view = session.terminalView
    let foreground = view.nativeForegroundColor
    let background = view.nativeBackgroundColor
    let selection = view.selectedTextBackgroundColor
    let selectedText = view.selectedTextForegroundColor
    let caretText = view.caretTextColor
    var preferences = TerminalPreferences()

    preferences.themeID = "nord"
    session.applyAppearance(preferences)
    preferences.themeID = "gruvbox-dark"
    session.applyAppearance(preferences)
    #expect(view.selectedTextBackgroundColor != selection)

    preferences.themeID = nil
    session.applyAppearance(preferences)
    #expect(view.colorTheme == nil)
    #expect(view.nativeForegroundColor == foreground)
    #expect(view.nativeBackgroundColor == background)
    #expect(view.selectedTextBackgroundColor == selection)
    #expect(view.selectedTextForegroundColor == selectedText)
    #expect(view.caretTextColor == caretText)
  }

  @Test func anUnknownColorThemeUsesTheSystemColors() {
    let session = makeClosedSession()
    let background = session.terminalView.nativeBackgroundColor
    var preferences = TerminalPreferences()
    preferences.themeID = "removed-theme"

    session.applyAppearance(preferences)

    #expect(session.terminalView.colorTheme == nil)
    #expect(session.terminalView.nativeBackgroundColor == background)
  }

  @Test func anImportedThemeSetsItsOwnSelectedAndCursorTextColors() {
    let session = makeClosedSession()
    let view = session.terminalView
    var preferences = TerminalPreferences()
    preferences.importTheme(
      TerminalTheme(
        id: "imported.Mine", name: "Mine", foreground: "#111111", background: "#EEEEEE",
        cursor: "#222222", selection: "#111111", ansi: Array(repeating: "#333333", count: 16),
        selectedText: "#FFFFFF", cursorText: "#ABCDEF"))

    session.applyAppearance(preferences)

    #expect(view.colorTheme?.id == "imported.Mine")
    #expect(view.selectedTextForegroundColor == NSColor(themeHex: "#FFFFFF"))
    #expect(view.caretTextColor == NSColor(themeHex: "#ABCDEF"))
  }

  private func makeClosedSession() -> TerminalSession {
    _ = NSApplication.shared
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/sh"
    preferences.loginShell = false
    preferences.interactiveShell = false
    preferences.integrationEnabled = false
    let session = TerminalSession(directory: "/", preferences: preferences)
    // Appearance is renderer-only; do not leave a shell or monitoring timer alive for these tests.
    session.close()
    return session
  }
}
