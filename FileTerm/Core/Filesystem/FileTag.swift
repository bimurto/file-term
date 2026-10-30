import Foundation

public enum FileTagColor: String, CaseIterable, Codable, Sendable {
  case gray, green, purple, blue, yellow, red, orange

  public var title: String { rawValue.capitalized }
}

/// A tag listed in Settings › Tags and shown in the sidebar.
public struct FileTag: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var name: String
  public var color: FileTagColor

  public var id: String { name }

  public init(name: String, color: FileTagColor) {
    self.name = name
    self.color = color
  }

  public static let defaults = FileTagColor.allCases.map { FileTag(name: $0.title, color: $0) }

  /// Finder stores tags as "Name\nColorIndex" in some places, so only the name is compared.
  public func isOn(_ entry: FileEntry) -> Bool {
    entry.tags.contains { tag in
      (tag.components(separatedBy: "\n").first ?? tag).caseInsensitiveCompare(name) == .orderedSame
    }
  }

  /// The list with a new tag added, or nil when the name is blank or already listed.
  public static func adding(_ name: String, color: FileTagColor, to tags: [FileTag]) -> [FileTag]? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
    else { return nil }
    return tags + [FileTag(name: trimmed, color: color)]
  }
}
