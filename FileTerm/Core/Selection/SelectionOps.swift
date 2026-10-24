import Foundation

public enum SelectionMatchField: String, CaseIterable, Codable, Sendable {
  case name = "Name"
  case fileExtension = "Extension"
  case tag = "Tag"
}

public enum SelectionMode: String, CaseIterable, Codable, Sendable {
  case replace = "Replace Selection"
  case add = "Add to Selection"
  case remove = "Remove from Selection"
}

/// Case-insensitive matcher. A pattern with `*` or `?` is a whole-value wildcard; otherwise it is
/// a "contains" match.
public struct PatternMatcher: Sendable {
  private let needle: String
  private let regex: NSRegularExpression?

  public init(_ pattern: String) {
    let trimmed = pattern.trimmingCharacters(in: .whitespaces)
    needle = trimmed.lowercased()
    if trimmed.contains("*") || trimmed.contains("?") {
      var source = "^"
      for character in trimmed {
        switch character {
        case "*": source += ".*"
        case "?": source += "."
        default: source += NSRegularExpression.escapedPattern(for: String(character))
        }
      }
      regex = try? NSRegularExpression(pattern: source + "$", options: [.caseInsensitive])
    } else {
      regex = nil
    }
  }

  public var isEmpty: Bool { needle.isEmpty }

  public func matches(_ value: String) -> Bool {
    guard !needle.isEmpty else { return false }
    if let regex {
      return regex.firstMatch(
        in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    return value.lowercased().contains(needle)
  }
}

public struct QuickSelectCriteria: Equatable, Sendable {
  public var field: SelectionMatchField
  public var pattern: String
  public var mode: SelectionMode

  public init(
    field: SelectionMatchField = .name, pattern: String = "", mode: SelectionMode = .replace
  ) {
    self.field = field
    self.pattern = pattern
    self.mode = mode
  }

  public func matches(_ entry: FileEntry) -> Bool {
    switch field {
    case .name: return PatternMatcher(pattern).matches(entry.name)
    case .fileExtension:
      let wanted = pattern.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
      guard !wanted.isEmpty, entry.kind != .directory else { return false }
      return (entry.name as NSString).pathExtension.lowercased() == wanted
    case .tag:
      let matcher = PatternMatcher(pattern)
      return entry.tags.contains { matcher.matches($0) }
    }
  }

  /// The selection that would result, and how many entries matched.
  public func preview(entries: [FileEntry], current: Set<Location>) -> (
    matched: Int, resulting: Set<Location>
  ) {
    let matched = Set(entries.filter(matches).map(\.id))
    switch mode {
    case .replace: return (matched.count, matched)
    case .add: return (matched.count, current.union(matched))
    case .remove: return (matched.count, current.subtracting(matched))
    }
  }
}

public enum SelectionOps {
  public static func invert(all entries: [FileEntry], selected: Set<Location>) -> Set<Location> {
    Set(entries.map(\.id)).subtracting(selected)
  }
}
