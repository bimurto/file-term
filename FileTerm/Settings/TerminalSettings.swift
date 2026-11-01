import FileTermCore
import Foundation

/// Settings-only types deliberately do not depend on the terminal renderer.
enum TerminalFollowMode: String, Codable, CaseIterable, Identifiable {
  case active, first, second, unlinked
  var id: String { rawValue }
  var title: String {
    switch self {
    case .active: "Active Pane"
    case .first: "First Pane"
    case .second: "Second Pane"
    case .unlinked: "Unlinked"
    }
  }
}

enum TerminalCursorStyle: String, Codable, CaseIterable, Identifiable {
  case block, underline, bar
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct TerminalPreferences: Codable, Equatable {
  var shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  var loginShell = true
  var interactiveShell = true
  var integrationEnabled = true
  var reverseSync = true
  var followMode: TerminalFollowMode = .active
  var fontName = "Menlo"
  var fontSize: Double = 13
  var cursorStyle: TerminalCursorStyle = .block
  var scrollbackLines = 10_000
  /// Nil uses the system colors. Optional so preferences saved before this field still decode.
  var themeID: String?
  /// Optional for the same reason as `themeID`.
  var importedThemes: [TerminalTheme]?

  /// The shipped themes, then the imported ones.
  var colorThemes: [TerminalTheme] { ThemeLibrary.terminalThemes + (importedThemes ?? []) }

  /// Adds a theme and selects it. Importing the same name again replaces the earlier one.
  mutating func importTheme(_ theme: TerminalTheme) {
    importedThemes = (importedThemes ?? []).filter { $0.id != theme.id } + [theme]
    themeID = theme.id
  }

  /// Removes an imported theme. If it's in use, the terminal goes back to the system colors.
  mutating func removeImportedTheme(id: String) {
    importedThemes?.removeAll { $0.id == id }
    if themeID == id { themeID = nil }
  }
}

enum TerminalDock: String, Codable, CaseIterable, Identifiable {
  case bottom, right
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

/// Stored with each window rather than with the shared terminal preferences.
struct TerminalPanelState: Codable, Equatable {
  var isVisible = false
  var dock: TerminalDock = .bottom
  var size: Double = 220
}
