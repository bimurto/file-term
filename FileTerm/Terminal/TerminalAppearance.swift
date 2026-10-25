import AppKit
import SwiftTerm

extension TerminalSession {
  /// Updates only the existing renderer; shell and integration settings apply to new sessions.
  func applyAppearance(_ preferences: TerminalPreferences) {
    // Persisted preferences may bypass the settings UI's bounds. Never pass unsafe sizes to AppKit.
    let fontSize = preferences.fontSize.isFinite ? min(48, max(8, preferences.fontSize)) : 13
    let font =
      NSFont(name: preferences.fontName, size: CGFloat(fontSize))
      ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    if terminalView.font != font { terminalView.font = font }

    let terminal = terminalView.getTerminal()
    let scrollback = min(100_000, max(0, preferences.scrollbackLines))
    if terminal.options.scrollback != scrollback { terminalView.changeScrollback(scrollback) }

    let cursor: CursorStyle =
      switch preferences.cursorStyle {
      case .block: .steadyBlock
      case .underline: .steadyUnderline
      case .bar: .steadyBar
      }
    if terminal.options.cursorStyle != cursor { terminal.setCursorStyle(cursor) }
  }
}
