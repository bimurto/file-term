import Foundation

/// Which application edits files with these extensions (Settings › Editing).
public struct EditorMapping: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var applicationPath: String
  /// Lowercase, without the leading dot. A name such as `tar.gz` matches whole file suffixes.
  public var extensions: [String]

  public init(id: UUID = UUID(), applicationPath: String, extensions: [String]) {
    self.id = id
    self.applicationPath = applicationPath
    self.extensions = Self.normalized(extensions)
  }

  public var displayName: String {
    ((applicationPath as NSString).lastPathComponent as NSString).deletingPathExtension
  }

  /// Splits "swift, .MD txt" into `["swift", "md", "txt"]`.
  public static func parseExtensions(_ text: String) -> [String] {
    normalized(text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init))
  }

  private static func normalized(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.compactMap { value in
      var item = value.trimmingCharacters(in: .whitespaces).lowercased()
      while item.hasPrefix(".") { item.removeFirst() }
      return item.isEmpty || !seen.insert(item).inserted ? nil : item
    }
  }

  /// The first mapping, in list order, that lists one of the file's extensions.
  public static func mapping(for fileName: String, in mappings: [EditorMapping]) -> EditorMapping? {
    let name = fileName.lowercased()
    return mappings.first { mapping in
      mapping.extensions.contains { name.hasSuffix("." + $0) }
    }
  }
}
