import Foundation

/// Removes credentials from text before it reaches a log, which people copy and share. Tool commands
/// and Git output can hold anything, so this matches common shapes and can't promise to catch all.
public enum LogRedactor {
  public static let mask = "•••"
  private static let value = #"(?:"[^"]*"|'[^']*'|[^\s"',;&]+)"#
  private static let secretWord =
    "(?:password|passwd|pwd|passphrase|secret|token|api[-_]?key|access[-_]?key|private[-_]?key|auth)"

  private static let rules: [(pattern: NSRegularExpression, template: String)] = [
    // https://user:token@host and https://token@host
    (#"\b([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s@]+@"#, "$1\(mask)@"),
    // Authorization: Bearer abc
    (
      #"(?i)\b((?:proxy-)?authorization\s*[:=]\s*)(?:(?:bearer|basic|token)\s+)?"# + value,
      "$1\(mask)"
    ),
    // curl -u user:password
    (#"(^|\s)(-u\s*|--user[=\s]\s*)[^\s:]+:\S+"#, "$1$2\(mask)"),
    // --password abc, --api-key=abc
    (
      "(?i)(^|\\s)(--?[a-z0-9-]*\(secretWord)[a-z0-9-]*)(=|\\s+)\(value)",
      "$1$2$3\(mask)"
    ),
    // API_TOKEN=abc, and ?token=abc in a URL
    (
      "(?i)(\\b[a-z0-9_.-]*\(secretWord)[a-z0-9_.-]*\\s*=\\s*)\(value)",
      "$1\(mask)"
    ),
    // Tokens recognisable on their own: GitHub, Slack, AWS key IDs and sk- style API keys.
    (
      #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,})\b"#,
      mask
    ),
  ].map { (pattern: try! NSRegularExpression(pattern: $0.0), template: $0.1) }

  private static let personalPath = try! NSRegularExpression(pattern: #"/Users/[^/\s,\t]+"#)

  public static func redact(_ text: String) -> String {
    rules.reduce(text) { apply($1.pattern, $1.template, to: $0) }
  }

  /// Replaces home folders with `~`, for logs someone wants to share without their user name.
  public static func hidingPersonalPaths(_ text: String) -> String {
    apply(personalPath, "~", to: text)
  }

  private static func apply(
    _ pattern: NSRegularExpression, _ template: String, to text: String
  ) -> String {
    pattern.stringByReplacingMatches(
      in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
  }
}
