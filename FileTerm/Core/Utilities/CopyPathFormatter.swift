import Foundation

public enum CopyPathFormat: String, CaseIterable, Sendable {
  case unix, fileURL, decodedURL, name, terminal, windows
}

public enum CopyPathFormatter {
  /// Formats local file URLs without resolving symlinks or checking existence.
  /// Windows format only replaces separators: no drive letter, volume mapping, or UNC mapping
  /// is inferred. A macOS path may still contain characters Windows cannot represent.
  /// Decoded URLs are for display/copy, not guaranteed to be valid navigable URL strings.
  public static func string(for url: URL, format: CopyPathFormat) throws -> String {
    guard url.isFileURL else { throw FileUtilityError.nonLocalURL }
    switch format {
    case .unix: return url.path
    case .fileURL: return url.absoluteString
    case .decodedURL: return url.absoluteString.removingPercentEncoding ?? url.absoluteString
    case .name: return url.lastPathComponent
    case .terminal: return shellQuoted(url.path)
    case .windows: return url.path.replacingOccurrences(of: "/", with: "\\")
    }
  }

  /// One literal POSIX-shell argument, safe for spaces, quotes, newlines and substitutions.
  public static func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
