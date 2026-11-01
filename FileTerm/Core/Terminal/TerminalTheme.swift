import Foundation

/// A built-in terminal color theme loaded from a data file. Colors are `#RRGGBB`.
public struct TerminalTheme: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var order: Int
  public var foreground: String
  public var background: String
  public var cursor: String
  public var selection: String
  /// The 16 ANSI colors, normal then bright.
  public var ansi: [String]

  public init(
    id: String, name: String, order: Int = 0, foreground: String, background: String,
    cursor: String, selection: String, ansi: [String]
  ) {
    self.id = id
    self.name = name
    self.order = order
    self.foreground = foreground
    self.background = background
    self.cursor = cursor
    self.selection = selection
    self.ansi = ansi
  }

  /// Reads theme files in display order. A file that is not a complete, valid theme is skipped.
  public static func load(from urls: [URL]) -> [TerminalTheme] {
    let themes = urls.compactMap { url in
      (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    return themes.filter(\.isValid).sorted { ($0.order, $0.name) < ($1.order, $1.name) }
  }

  /// The chosen theme, or nil for the system colors when nothing is chosen or it no longer exists.
  public static func theme(id: String?, in themes: [TerminalTheme]) -> TerminalTheme? {
    themes.first { $0.id == id }
  }

  private var isValid: Bool {
    ansi.count == 16
      && ([foreground, background, cursor, selection] + ansi).allSatisfy {
        AppTheme.components(hex: $0) != nil
      }
  }
}
