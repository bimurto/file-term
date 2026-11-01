import Foundation

/// A saved place. Local folders (including iCloud Drive) and saved connections share one list.
public struct FavoriteItem: Codable, Hashable, Identifiable, Sendable {
  public enum Target: Codable, Hashable, Sendable {
    case local(path: String)
    /// A saved connection with its own list of starting paths. An empty list opens the profile's path.
    case connection(profileID: UUID, paths: [String])
  }

  public var id: UUID
  public var name: String
  public var target: Target

  public init(id: UUID = UUID(), name: String, target: Target) {
    self.id = id
    self.name = name
    self.target = target
  }

  public static var iCloudDrivePath: String {
    NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
  }
}

public struct FavoriteGroup: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var items: [FavoriteItem]

  public init(id: UUID = UUID(), name: String, items: [FavoriteItem] = []) {
    self.id = id
    self.name = name
    self.items = items
  }
}

/// A top-level entry: either a favorite or a group of favorites. Groups do not nest.
public enum FavoriteNode: Codable, Hashable, Identifiable, Sendable {
  case item(FavoriteItem)
  case group(FavoriteGroup)

  public var id: UUID {
    switch self {
    case .item(let item): item.id
    case .group(let group): group.id
    }
  }

  public var name: String {
    switch self {
    case .item(let item): item.name
    case .group(let group): group.name
    }
  }
}

extension Array where Element == FavoriteNode {
  /// Every favorite in list order, groups expanded.
  public var allItems: [FavoriteItem] {
    flatMap { node -> [FavoriteItem] in
      switch node {
      case .item(let item): [item]
      case .group(let group): group.items
      }
    }
  }

  public func item(_ id: UUID) -> FavoriteItem? { allItems.first { $0.id == id } }

  /// Adds a favorite at the end, unless one with the same target exists anywhere in the list.
  public func adding(_ item: FavoriteItem) -> [FavoriteNode] {
    allItems.contains { $0.target == item.target } ? self : self + [.item(item)]
  }

  /// Removes a favorite or a whole group wherever it is.
  public func removing(_ id: UUID) -> [FavoriteNode] {
    compactMap { node -> FavoriteNode? in
      switch node {
      case .item(let item): return item.id == id ? nil : node
      case .group(var group):
        if group.id == id { return nil }
        group.items.removeAll { $0.id == id }
        return .group(group)
      }
    }
  }

  /// Moves a favorite into a group, or to the top level when `groupID` is nil. Groups cannot be
  /// moved into groups, and an unknown id or group leaves the list unchanged.
  public func moving(_ id: UUID, intoGroup groupID: UUID?) -> [FavoriteNode] {
    guard let item = item(id) else { return self }
    if let groupID,
      !contains(where: { if case .group(let g) = $0 { g.id == groupID } else { false } })
    {
      return self
    }
    var result = removing(id)
    if let groupID {
      result = result.map { node in
        guard case .group(var group) = node, group.id == groupID else { return node }
        group.items.append(item)
        return .group(group)
      }
    } else {
      result.append(.item(item))
    }
    return result
  }

  /// Replaces the favorite or group with the same id.
  public func replacing(_ replacement: FavoriteNode) -> [FavoriteNode] {
    map { node -> FavoriteNode in
      if node.id == replacement.id { return replacement }
      guard case .group(var group) = node, case .item(let item) = replacement,
        let index = group.items.firstIndex(where: { $0.id == item.id })
      else { return node }
      group.items[index] = item
      return .group(group)
    }
  }
}
