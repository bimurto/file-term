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
/// a "contains" match. Wildcards compare whole characters without backtracking over earlier stars,
/// so a pattern's cost stays in proportion to its length times the name's.
public struct PatternMatcher: Sendable {
  private let needle: String
  private let wildcard: [Character]?

  public init(_ pattern: String) {
    let trimmed = pattern.trimmingCharacters(in: .whitespaces)
    needle = trimmed.lowercased()
    wildcard = trimmed.contains("*") || trimmed.contains("?") ? Array(needle) : nil
  }

  public var isEmpty: Bool { needle.isEmpty }

  public func matches(_ value: String) -> Bool {
    guard !needle.isEmpty else { return false }
    if let wildcard { return Self.matches(Array(value.lowercased()), wildcard) }
    return value.lowercased().contains(needle)
  }

  /// A later star can take over anything an earlier one matched, so only the last star needs
  /// retrying.
  private static func matches(_ value: [Character], _ pattern: [Character]) -> Bool {
    var position = 0
    var next = 0
    var star: Int?
    var starPosition = 0
    while position < value.count {
      if next < pattern.count, pattern[next] == "*" {
        star = next
        starPosition = position
        next += 1
      } else if next < pattern.count, pattern[next] == "?" || pattern[next] == value[position] {
        position += 1
        next += 1
      } else if let star {
        starPosition += 1
        position = starPosition
        next = star + 1
      } else {
        return false
      }
    }
    return pattern[next...].allSatisfy { $0 == "*" }
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
