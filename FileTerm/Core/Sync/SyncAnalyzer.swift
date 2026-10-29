import Foundation

/// Compares two folder trees by relative path, using dates and sizes only (not file contents).
public enum SyncAnalyzer {
  /// Modification times closer than this count as equal (FAT and some servers keep 2 s).
  public static let dateTolerance: TimeInterval = 2

  public static func analyze(
    left: Location, right: Location, options: SyncOptions, registry: ProviderRegistry
  ) async throws -> [SyncAction] {
    if let bad = options.excludes.first(where: { !$0.isValid }) {
      throw SyncError.invalidFilter(bad.pattern)
    }
    guard let leftProvider = registry.provider(for: left.providerID),
      let rightProvider = registry.provider(for: right.providerID)
    else { throw SyncError.missingProvider(left.providerID) }
    async let leftTree = scan(left, with: leftProvider, options: options)
    async let rightTree = scan(right, with: rightProvider, options: options)
    return try compare(left: await leftTree, right: await rightTree, options: options)
  }

  /// Relative path to entry for every file and folder below `root` that the options include.
  static func scan(
    _ root: Location, with provider: any FileSystemProvider, options: SyncOptions
  ) async throws -> [String: FileEntry] {
    var result: [String: FileEntry] = [:]
    var queue: [(Location, String)] = [(root, "")]
    var index = 0
    while index < queue.count {
      try Task.checkCancellation()
      let (folder, prefix) = queue[index]
      index += 1
      let entries: [FileEntry]
      do {
        entries = try await provider.list(folder, includeHidden: options.hidden)
      } catch {
        // An unreadable subfolder is left out; the root itself must be readable.
        if index == 1 { throw error }
        continue
      }
      for entry in entries {
        if !options.hidden && entry.isHidden { continue }
        let relative = prefix.isEmpty ? entry.name : prefix + "/" + entry.name
        if options.excludes.contains(where: { $0.matches(relativePath: relative) }) { continue }
        switch entry.kind {
        case .file:
          result[relative] = entry
        case .directory:
          guard options.subfolders else { continue }
          result[relative] = entry
          queue.append((entry.location, relative))
        case .symbolicLink, .other:
          continue
        }
      }
    }
    return result
  }

  static func compare(
    left: [String: FileEntry], right: [String: FileEntry], options: SyncOptions
  ) -> [SyncAction] {
    var actions: [SyncAction] = []
    let paths = Set(left.keys).union(right.keys).sorted()
    var removedFolders: [String] = []
    for path in paths {
      let l = left[path]
      let r = right[path]
      switch (l, r) {
      case (let l?, let r?):
        if let action = compareBoth(path, l, r, options) { actions.append(action) }
      case (let l?, nil):
        if let action = orphanOrAdd(
          path, entry: l, side: .left, tree: left, options, &removedFolders)
        {
          actions.append(action)
        }
      case (nil, let r?):
        if let action = orphanOrAdd(
          path, entry: r, side: .right, tree: right, options, &removedFolders)
        {
          actions.append(action)
        }
      case (nil, nil): break
      }
    }
    // Deleting a folder removes everything in it; its own rows would only repeat that.
    return actions.filter { action in
      !(action.kind == .delete
        && removedFolders.contains { action.relativePath.hasPrefix($0 + "/") })
    }
  }

  private static func orphanOrAdd(
    _ path: String, entry: FileEntry, side: SyncAction.Side, tree: [String: FileEntry],
    _ options: SyncOptions, _ removedFolders: inout [String]
  ) -> SyncAction? {
    // `side` holds the item; the other side is where it would be added.
    let other: SyncAction.Side = side == .left ? .right : .left
    let sourceSide: SyncOptions.Direction = side == .left ? .leftToRight : .rightToLeft
    let isDirectory = entry.kind == .directory
    func make(_ kind: SyncAction.Kind, towards: SyncAction.Side) -> SyncAction {
      SyncAction(
        relativePath: path, kind: kind, towards: towards, isDirectory: isDirectory,
        left: side == .left ? entry : nil, right: side == .right ? entry : nil)
    }
    if options.direction == .bothWays || options.direction == sourceSide {
      guard options.addItems else { return nil }
      if isDirectory && options.skipEmptyFolders {
        let hasFile = tree.contains { $0.value.kind == .file && $0.key.hasPrefix(path + "/") }
        if !hasFile { return nil }
      }
      return make(.add, towards: other)
    }
    guard options.deleteOrphans else { return nil }
    if isDirectory { removedFolders.append(path) }
    return make(.delete, towards: side)
  }

  private static func compareBoth(
    _ path: String, _ l: FileEntry, _ r: FileEntry, _ options: SyncOptions
  ) -> SyncAction? {
    let isDirectory = l.kind == .directory
    if (l.kind == .directory) != (r.kind == .directory) {
      let towards: SyncAction.Side = options.direction == .rightToLeft ? .left : .right
      return SyncAction(
        relativePath: path, kind: .conflict, towards: towards, isDirectory: false,
        left: l, right: r, isChecked: false, isRunnable: false)
    }
    if isDirectory { return nil }
    let offset = options.offsetSeconds
    let sizeDiffers =
      options.updateWhenSizeDiffers && l.size != nil && r.size != nil && l.size != r.size
    // Positive: the left file is newer once the right clock is corrected.
    var leftNewerBy: TimeInterval = 0
    if let lm = l.modifiedAt, let rm = r.modifiedAt {
      leftNewerBy = lm.timeIntervalSince(rm.addingTimeInterval(offset))
    }
    let leftIsNewer = leftNewerBy > dateTolerance
    let rightIsNewer = leftNewerBy < -dateTolerance
    func action(_ kind: SyncAction.Kind, towards: SyncAction.Side, checked: Bool = true)
      -> SyncAction
    {
      SyncAction(
        relativePath: path, kind: kind, towards: towards, isDirectory: false, left: l, right: r,
        isChecked: checked)
    }
    switch options.direction {
    case .leftToRight:
      let older = options.updateWhenOlder && leftIsNewer
      return older || sizeDiffers ? action(.update, towards: .right) : nil
    case .rightToLeft:
      let older = options.updateWhenOlder && rightIsNewer
      return older || sizeDiffers ? action(.update, towards: .left) : nil
    case .bothWays:
      if options.updateWhenOlder || sizeDiffers {
        if leftIsNewer { return action(.update, towards: .right) }
        if rightIsNewer { return action(.update, towards: .left) }
      }
      // Same time, different size: no side can be told to win.
      if sizeDiffers { return action(.conflict, towards: .right, checked: false) }
      return nil
    }
  }
}
