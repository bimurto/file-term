import Darwin
import Foundation

public struct SyncFilter: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var pattern: String
  public var isRegex: Bool

  public init(id: UUID = UUID(), pattern: String, isRegex: Bool = false) {
    self.id = id
    self.pattern = pattern
    self.isRegex = isRegex
  }

  /// False when a regular expression does not compile; blank patterns are ignored, not invalid.
  public var isValid: Bool {
    !isRegex || pattern.isEmpty || (try? NSRegularExpression(pattern: pattern)) != nil
  }

  /// A glob without a slash matches an item's name; one with a slash matches the whole relative
  /// path. A regular expression is searched in the relative path. Matching ignores case.
  public func matches(relativePath: String) -> Bool {
    guard !pattern.isEmpty else { return false }
    if isRegex {
      guard
        let expression = try? NSRegularExpression(
          pattern: pattern, options: [.caseInsensitive])
      else { return false }
      let range = NSRange(relativePath.startIndex..., in: relativePath)
      return expression.firstMatch(in: relativePath, range: range) != nil
    }
    let subject =
      pattern.contains("/")
      ? relativePath : (relativePath as NSString).lastPathComponent
    return fnmatch(pattern, subject, FNM_CASEFOLD) == 0
  }
}

public struct SyncOptions: Codable, Hashable, Sendable {
  public enum Direction: String, Codable, CaseIterable, Sendable {
    case leftToRight, rightToLeft, bothWays
  }

  public enum OffsetUnit: String, Codable, CaseIterable, Sendable {
    case seconds, hours
  }

  public var direction: Direction = .leftToRight
  public var subfolders = true
  public var hidden = false
  public var addItems = true
  public var skipEmptyFolders = false
  public var updateWhenOlder = true
  public var updateWhenSizeDiffers = false
  /// Off by default: orphans are only proposed when the user asks for it.
  public var deleteOrphans = false
  /// Added to the right side's modification dates before comparing, for clocks that disagree.
  public var timeOffset: Double = 0
  public var offsetUnit: OffsetUnit = .seconds
  public var excludes: [SyncFilter] = []

  public init() {}

  public var offsetSeconds: TimeInterval {
    offsetUnit == .hours ? timeOffset * 3600 : timeOffset
  }
}

public struct SyncAction: Identifiable, Hashable, Sendable {
  public enum Kind: String, Sendable { case add, update, delete, conflict }
  public enum Side: String, Sendable { case left, right }

  /// The relative path; a path has at most one action.
  public var id: String { relativePath }
  public let relativePath: String
  public var kind: Kind
  /// The side that changes: receives the item, or loses it for a delete.
  public var towards: Side
  public let isDirectory: Bool
  public let left: FileEntry?
  public let right: FileEntry?
  public var isChecked: Bool
  /// False for a file on one side against a folder on the other; those can only be reported.
  public let isRunnable: Bool

  public init(
    relativePath: String, kind: Kind, towards: Side, isDirectory: Bool,
    left: FileEntry?, right: FileEntry?, isChecked: Bool = true, isRunnable: Bool = true
  ) {
    self.relativePath = relativePath
    self.kind = kind
    self.towards = towards
    self.isDirectory = isDirectory
    self.left = left
    self.right = right
    self.isChecked = isChecked && isRunnable
    self.isRunnable = isRunnable
  }

  /// The item that is copied; nil for a delete.
  public var source: FileEntry? { towards == .right ? left : right }
  /// The item that is replaced or removed; nil for an add.
  public var destination: FileEntry? { towards == .right ? right : left }
}

public enum SyncError: Error, LocalizedError, Sendable {
  case invalidFilter(String)
  case missingProvider(String)

  public var errorDescription: String? {
    switch self {
    case .invalidFilter(let pattern): "“\(pattern)” is not a valid regular expression."
    case .missingProvider: "A connection used by this sync is no longer open."
    }
  }
}

extension SyncAction {
  /// Where this action's item lives (or would live) under the given side's root.
  public func location(on side: Side, left: Location, right: Location) -> Location {
    let root = side == .left ? left : right
    let base = root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
    return Location(providerID: root.providerID, path: base + "/" + relativePath)
  }

  /// The folder that holds this action's item on the given side.
  public func parentLocation(on side: Side, left: Location, right: Location) -> Location {
    let item = location(on: side, left: left, right: right)
    let parent = (item.path as NSString).deletingLastPathComponent
    return Location(providerID: item.providerID, path: parent.isEmpty ? "/" : parent)
  }
}
