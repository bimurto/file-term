import Foundation

public enum RenameIssue: String, Hashable, Sendable {
  /// Two items would get the same name in one folder (ignoring case).
  case duplicateName
  /// The new name is empty, `.`, `..`, too long, or contains `/`, `:` or a null character.
  case invalidName
  /// The new name is already taken by an item that is not being renamed.
  case nameExists
  /// A file would get a different extension, so it may open in another application.
  case extensionChanged

  /// Errors block Rename; a warning needs the user to allow it.
  public var isError: Bool { self != .extensionChanged }

  public var message: String {
    switch self {
    case .duplicateName: "Duplicate name"
    case .invalidName: "Invalid name"
    case .nameExists: "Name already exists"
    case .extensionChanged: "Extension changes"
    }
  }
}

public struct RenameRow: Identifiable, Hashable, Sendable {
  public var id: Location { item.location }
  public let item: RenameItem
  public let proposed: String
  public var issues: [RenameIssue] = []
  public var original: String { item.name }
  public var isChanged: Bool { proposed != item.name }
  public var hasError: Bool { issues.contains { $0.isError } }
  public var hasWarning: Bool { issues.contains { !$0.isError } }
}

public enum BatchRenamePlanner {
  /// The proposed names, in the order the items are given: sequence numbers follow that order.
  /// `existingNames` maps a folder path to the names it holds, to catch names that are taken.
  public static func preview(
    items: [RenameItem], rules: [RenameRule], now: Date = Date(),
    existingNames: [String: Set<String>] = [:]
  ) -> [RenameRow] {
    let rows = items.enumerated().map { index, item in
      let name = rules.reduce(item.name) { $1.apply(to: $0, item: item, index: index, now: now) }
      return RenameRow(item: item, proposed: name)
    }
    return validated(rows, existingNames: existingNames)
  }

  private static func folder(_ row: RenameRow) -> String {
    (row.item.location.path as NSString).deletingLastPathComponent
  }

  private static func key(_ folder: String, _ name: String) -> String {
    folder + "\u{0}" + name.lowercased()
  }

  private static func validated(_ rows: [RenameRow], existingNames: [String: Set<String>])
    -> [RenameRow]
  {
    var holders: [String: Int] = [:]
    for row in rows { holders[key(folder(row), row.proposed), default: 0] += 1 }
    // Names the batch gives up: free for another item once the sequencer has moved it away.
    let vacated = Set(rows.filter(\.isChanged).map { key(folder($0), $0.original) })
    return rows.map { row in
      guard row.isChanged else { return row }
      var row = row
      let name = row.proposed
      let place = folder(row)
      if name.isEmpty || name == "." || name == ".." || name.utf8.count > 255
        || name.contains(where: { $0 == "/" || $0 == ":" || $0 == "\0" })
      {
        row.issues.append(.invalidName)
      }
      if holders[key(place, name), default: 0] > 1 { row.issues.append(.duplicateName) }
      let taken = existingNames[place]?.contains { $0.lowercased() == name.lowercased() } == true
      if taken && !vacated.contains(key(place, name)) && !row.issues.contains(.duplicateName) {
        row.issues.append(.nameExists)
      }
      if !row.item.isDirectory,
        (name as NSString).pathExtension != (row.original as NSString).pathExtension
      {
        row.issues.append(.extensionChanged)
      }
      return row
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

  /// Runs the steps in order. If one fails or is cancelled, the finished ones are renamed back, so
  /// no item stays under a temporary name. Throws `PartialTransferError` if that isn't possible.
  public static func perform(
    _ steps: [RenameStep], before: @Sendable () async throws -> Void,
    rename: @escaping @Sendable (RenameStep) async throws -> Void
  ) async throws {
    var finished: [RenameStep] = []
    do {
      for step in steps {
        try await before()
        try await rename(step)
        finished.append(step)
      }
    } catch {
      let reversals = finished.reversed().map { step in
        let folder = (step.path as NSString).deletingLastPathComponent
        return RenameStep(
          path: (folder as NSString).appendingPathComponent(step.name),
          name: (step.path as NSString).lastPathComponent)
      }
      // A new task, because a cancelled one would also stop the calls that put the names back.
      let stranded = await Task {
        var stranded: [String] = []
        for reversal in reversals {
          do { try await rename(reversal) } catch { stranded.append(reversal.path) }
        }
        return stranded
      }.value
      guard stranded.isEmpty else {
        throw PartialTransferError(
          "\(error.localizedDescription) These items couldn't be renamed back: "
            + stranded.joined(separator: ", ") + ".")
      }
      throw error
    }
  }
}
