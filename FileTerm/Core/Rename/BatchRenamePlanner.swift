import Foundation

public struct RenameRow: Identifiable, Hashable, Sendable {
  public var id: Location { item.location }
  public let item: RenameItem
  public let proposed: String
  public var original: String { item.name }
  public var isChanged: Bool { proposed != item.name }
}

public enum BatchRenamePlanner {
  /// The proposed names, in the order the items are given: sequence numbers follow that order.
  public static func preview(
    items: [RenameItem], rules: [RenameRule], now: Date = Date()
  ) -> [RenameRow] {
    items.enumerated().map { index, item in
      let name = rules.reduce(item.name) { $1.apply(to: $0, item: item, index: index, now: now) }
      return RenameRow(item: item, proposed: name)
    }
  }
}

public struct RenameStep: Equatable, Sendable {
  /// The item's current path.
  public let path: String
  /// The leaf name it gets, in the same folder.
  public let name: String
}

public enum RenameSequencer {
  /// Orders the renames so none lands on a name another item still holds. An item whose new name
  /// is another item's current name (a swap, a shift, or only a different case on a
  /// case-insensitive disk) first moves to a temporary name.
  public static func steps(
    for pairs: [(path: String, name: String)],
    temporaryName: () -> String = { ".fileterm-rename-" + UUID().uuidString }
  ) -> [RenameStep] {
    let changing = pairs.filter { ($0.path as NSString).lastPathComponent != $0.name }
    let held = Set(changing.map { $0.path.lowercased() })
    var first: [RenameStep] = []
    var direct: [RenameStep] = []
    var last: [RenameStep] = []
    for pair in changing {
      let folder = (pair.path as NSString).deletingLastPathComponent
      let target = (folder as NSString).appendingPathComponent(pair.name)
      if held.contains(target.lowercased()) {
        let temporary = temporaryName()
        first.append(RenameStep(path: pair.path, name: temporary))
        last.append(
          RenameStep(path: (folder as NSString).appendingPathComponent(temporary), name: pair.name))
      } else {
        direct.append(RenameStep(path: pair.path, name: pair.name))
      }
    }
    return first + direct + last
  }
}
