import Foundation

public enum SearchEngine: String, CaseIterable, Codable, Sendable {
  case builtIn = "Built-in"
  case spotlight = "Spotlight"

  public func isAvailable(for location: Location) -> Bool {
    self == .builtIn || location.providerID == "local"
  }

  public func unavailableReason(for location: Location) -> String? {
    isAvailable(for: location) ? nil : "Spotlight only searches local folders."
  }
}

public struct SearchQuery: Equatable, Sendable {
  public var text: String
  public var matchName: Bool
  public var matchExtension: Bool
  public var matchTag: Bool
  public var matchContents: Bool
  public var includeSubfolders: Bool
  public var includeHidden: Bool
  public var engine: SearchEngine

  public init(
    text: String = "", matchName: Bool = true, matchExtension: Bool = false,
    matchTag: Bool = false, matchContents: Bool = false, includeSubfolders: Bool = true,
    includeHidden: Bool = false, engine: SearchEngine = .builtIn
  ) {
    self.text = text
    self.matchName = matchName
    self.matchExtension = matchExtension
    self.matchTag = matchTag
    self.matchContents = matchContents
    self.includeSubfolders = includeSubfolders
    self.includeHidden = includeHidden
    self.engine = engine
  }

  public var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

  /// Metadata criteria (everything except contents).
  public func matchesMetadata(_ entry: FileEntry) -> Bool {
    let matcher = PatternMatcher(text)
    if matchName, matcher.matches(entry.name) { return true }
    if matchExtension, entry.kind != .directory {
      let ext = (entry.name as NSString).pathExtension
      if !ext.isEmpty, matcher.matches(ext) { return true }
    }
    if matchTag, entry.tags.contains(where: { matcher.matches($0) }) { return true }
    return false
  }
}

/// An open search: results live apart from the folder listing so closing returns to it.
public struct SearchScope: Equatable, Sendable {
  public var query: SearchQuery
  public var root: Location
  public var results: [FileEntry] = []
  public var isRunning = false
  public var errorMessage: String?

  public init(query: SearchQuery, root: Location) {
    self.query = query
    self.root = root
  }
}
