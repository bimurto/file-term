import Foundation

/// The terminal app File › Open in Terminal uses (Settings › General › Terminal Application).
/// This is separate from the built-in terminal panel.
public enum TerminalApplication: String, CaseIterable, Sendable {
  case terminal = "Terminal"
  case iTerm = "iTerm"
  case ghostty = "Ghostty"
  case warp = "Warp"

  public var title: String { rawValue }

  /// Where the app can live, in the order they are tried.
  public func candidatePaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
    let name: String
    switch self {
    case .terminal:
      return [
        "/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app",
      ]
    case .iTerm: name = "iTerm.app"
    case .ghostty: name = "Ghostty.app"
    case .warp: name = "Warp.app"
    }
    return ["/Applications/\(name)", homeDirectory + "/Applications/\(name)"]
  }

  /// The first place the app is found, or nil when it is not installed.
  public func applicationPath(
    homeDirectory: String = NSHomeDirectory(),
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> String? {
    candidatePaths(homeDirectory: homeDirectory).first(where: fileExists)
  }

  public var isInstalled: Bool { applicationPath() != nil }
}
