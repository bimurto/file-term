import AppKit
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
