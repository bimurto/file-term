import Foundation

/// A theme loaded from a JSON data file. Colors left out fall back to the system's.
public struct AppTheme: Codable, Equatable, Identifiable, Sendable {
  public enum Appearance: String, Codable, Sendable {
    case system, dark, light
  }

  public var id: String
  public var name: String
  public var order: Int
  public var appearance: Appearance
  public var accent: String?
  public var background: String?
  public var sidebar: String?
  public var foreground: String?

  public init(
    id: String, name: String, order: Int = 0, appearance: Appearance = .system,
    accent: String? = nil, background: String? = nil, sidebar: String? = nil,
    foreground: String? = nil
  ) {
    self.id = id
    self.name = name
    self.order = order
    self.appearance = appearance
    self.accent = accent
    self.background = background
    self.sidebar = sidebar
    self.foreground = foreground
  }

  public static let defaultID = "default"
  /// Used when a data file is missing, so the app always has a theme that follows the system.
  public static let fallback = AppTheme(id: defaultID, name: "Default")

  /// Reads theme files in display order. A file that is not a valid theme is skipped.
  public static func load(from urls: [URL]) -> [AppTheme] {
    let themes = urls.compactMap { url in
      (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AppTheme.self, from: $0) }
    }
    return themes.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
  }

  public static func theme(id: String, in themes: [AppTheme]) -> AppTheme {
    themes.first { $0.id == id } ?? themes.first { $0.id == defaultID } ?? fallback
  }

  /// Red, green and blue from 0 to 1 for a `#RRGGBB` color, or nil when it is malformed.
  public static func components(hex: String) -> (red: Double, green: Double, blue: Double)? {
    guard hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else {
      return nil
    }
    return (
      Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
      Double(value & 0xFF) / 255
    )
  }
}
