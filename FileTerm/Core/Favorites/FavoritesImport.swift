import Foundation

/// One local favorite found in an older configuration.
public struct ImportedFavorite: Hashable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let path: String
  public let group: String?
  /// The path is already a favorite, or appeared earlier in the file. Off in the preview.
  public let isDuplicate: Bool
}

public struct FavoritesImportPreview: Equatable, Sendable {
  public let favorites: [ImportedFavorite]
  /// Names of saved servers. Their fields are not read, so they are listed and left out.
  public let skippedRemote: [String]
}

public enum FavoritesImportError: Error, Equatable, LocalizedError {
  case unrecognized

  public var errorDescription: String? {
    switch self {
    case .unrecognized: "This file does not look like a ForkLift 3 favorites file."
    }
  }
}

/// Reads ForkLift 3's `Favorites.json`: `favorites` holds groups, whose `childItems` each have a
/// `type` and `attributes`. Keys are matched without regard to case.
public enum FavoritesImport {
  public static var forkLift3Path: String {
    NSHomeDirectory() + "/Library/Application Support/ForkLift/Favorites/Favorites.json"
  }

  public static func preview(data: Data, existing: [FavoriteNode]) throws -> FavoritesImportPreview
  {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let nodes = value("favorites", in: root) as? [[String: Any]]
    else { throw FavoritesImportError.unrecognized }
    var seen = Set(
      existing.allItems.compactMap { item -> String? in
        if case .local(let path) = item.target { return path }
        return nil
      })
    var favorites: [ImportedFavorite] = []
    var skipped: [String] = []

    func visit(_ node: [String: Any], group: String?) {
      let attributes = value("attributes", in: node) as? [String: Any] ?? [:]
      let title =
        ["name", "title"].lazy.compactMap { key in
          (value(key, in: attributes) ?? value(key, in: node)) as? String
        }.first
      if let children = value("childItems", in: node) as? [[String: Any]] {
        for child in children { visit(child, group: title ?? group) }
        return
      }
      guard let type = value("type", in: node) as? String else { return }
      guard type.lowercased() == "local" else {
        skipped.append(title ?? type)
        return
      }
      guard let raw = value("path", in: attributes) as? String, let path = localPath(raw) else {
        return
      }
      favorites.append(
        ImportedFavorite(
          id: UUID(), name: title ?? URL(fileURLWithPath: path).lastPathComponent, path: path,
          group: group, isDuplicate: !seen.insert(path).inserted))
    }
    for node in nodes { visit(node, group: nil) }
    return FavoritesImportPreview(favorites: favorites, skippedRemote: skipped)
  }

  /// Adds the favorites after what is there. Nothing existing is changed, and a path that is
  /// already a favorite is not added twice. A group with the same name receives the items.
  public static func merge(_ selected: [ImportedFavorite], into existing: [FavoriteNode])
    -> [FavoriteNode]
  {
    var result = existing
    for favorite in selected {
      let target = FavoriteItem.Target.local(path: favorite.path)
      guard !result.allItems.contains(where: { $0.target == target }) else { continue }
      let item = FavoriteItem(name: favorite.name, target: target)
      guard let name = favorite.group else {
        result.append(.item(item))
        continue
      }
      let index = result.firstIndex {
        if case .group(let group) = $0 { group.name == name } else { false }
      }
      if let index, case .group(var group) = result[index] {
        group.items.append(item)
        result[index] = .group(group)
      } else {
        result.append(.group(FavoriteGroup(name: name, items: [item])))
      }
    }
    return result
  }

  private static func value(_ key: String, in dictionary: [String: Any]) -> Any? {
    dictionary.first { $0.key.lowercased() == key.lowercased() }?.value
  }

  private static func localPath(_ raw: String) -> String? {
    if raw.hasPrefix("/") { return raw }
    if raw.hasPrefix("~/") { return NSHomeDirectory() + raw.dropFirst() }
    if let url = URL(string: raw), url.isFileURL { return url.path }
    return nil
  }
}
