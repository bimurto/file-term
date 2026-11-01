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
    let (leftScan, rightScan) = try await (leftTree, rightTree)
    return compare(
      left: leftScan.entries, right: rightScan.entries, options: options,
      keptLeft: leftScan.keptFolders, keptRight: rightScan.keptFolders,
      linksLeft: leftScan.links, linksRight: rightScan.links)
  }

  /// Every file and folder below `root` that the options include (by relative path), and the
  /// folders holding something they leave out: hidden items, exclusions, links and special files.
  /// Deleting one of those folders would delete what nobody was shown. `links` are the relative
  /// paths of the links and special files themselves, which an add must not land on.
  static func scan(
    _ root: Location, with provider: any FileSystemProvider, options: SyncOptions
  ) async throws -> (entries: [String: FileEntry], keptFolders: Set<String>, links: Set<String>) {
    var result: [String: FileEntry] = [:]
    var kept: Set<String> = []
    var links: Set<String> = []
    func keep(_ folder: String) {
      var path = folder
      while !path.isEmpty, kept.insert(path).inserted {
        path = (path as NSString).deletingLastPathComponent
      }
    }
    var queue: [(Location, String)] = [(root, "")]
    var index = 0
    while index < queue.count {
      try Task.checkCancellation()
      let (folder, prefix) = queue[index]
      index += 1
      let entries: [FileEntry]
      do {
        entries = try await provider.list(folder, includeHidden: true)
      } catch {
        // Skipping an unreadable folder would make everything in its twin look orphaned.
        if error is CancellationError { throw error }
        throw SyncError.unreadableFolder(folder.path, error.localizedDescription)
      }
      for entry in entries {
        let relative = prefix.isEmpty ? entry.name : prefix + "/" + entry.name
        if (!options.hidden && entry.isHidden)
          || options.excludes.contains(where: { $0.matches(relativePath: relative) })
        {
          keep(prefix)
          continue
        }
        switch entry.kind {
        case .file:
          result[relative] = entry
        case .directory:
          guard options.subfolders else { continue }
          result[relative] = entry
          queue.append((entry.location, relative))
        case .symbolicLink, .other:
          keep(prefix)
          links.insert(relative)
        }
      }
    }
    return (result, kept, links)
  }

  static func compare(
    left: [String: FileEntry], right: [String: FileEntry], options: SyncOptions,
    keptLeft: Set<String> = [], keptRight: Set<String> = [], linksLeft: Set<String> = [],
    linksRight: Set<String> = []
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
          path, entry: l, side: .left, tree: left, kept: keptLeft, options, &removedFolders)
        {
          actions.append(action)
        }
      case (nil, let r?):
        if let action = orphanOrAdd(
          path, entry: r, side: .right, tree: right, kept: keptRight, options, &removedFolders)
        {
          actions.append(action)
        }
      case (nil, nil): break
      }
    }
    // Deleting a folder removes everything in it; its own rows would only repeat that.
    let shown = actions.filter { action in
      !(action.kind == .delete
        && removedFolders.contains { action.relativePath.hasPrefix($0 + "/") })
    }
    let leftChecked = refusingClashes(
      in: shown, on: .left, existing: Set(left.keys), links: linksLeft)
    return refusingClashes(
      in: leftChecked, on: .right, existing: Set(right.keys), links: linksRight)
  }

  /// Whether a disk ignores case isn't known for every provider, so names that differ only in case
  /// are refused everywhere: on one that ignores it, the copy would replace the other item, and a
  /// delete of the other name would then remove the copy. An add onto a link would replace the link.
  private static func refusingClashes(
    in actions: [SyncAction], on side: SyncAction.Side, existing: Set<String>, links: Set<String>
  ) -> [SyncAction] {
    let adds = actions.filter { $0.kind == .add && $0.towards == side }.map(\.relativePath)
    var holders: [String: Set<String>] = [:]
    for path in existing.union(links).union(adds) {
      holders[path.lowercased(), default: []].insert(path)
    }
    var clashes: [String: String] = [:]
    for path in adds {
      let key = path.lowercased()
      if holders[key, default: []].count > 1 {
        clashes[key] = "name differs only in case"
      } else if links.contains(path) {
        clashes[key] = "link in the way"
      }
    }
    guard !clashes.isEmpty else { return actions }
    func refusal(for path: String) -> String? {
      var current = path.lowercased()
      while !current.isEmpty {
        if let reason = clashes[current] { return reason }
        current = (current as NSString).deletingLastPathComponent
      }
      return nil
    }
    return actions.map { action in
      guard action.kind == .add || action.kind == .delete, action.towards == side,
        let reason = refusal(for: action.relativePath)
      else { return action }
      return SyncAction(
        relativePath: action.relativePath, kind: .conflict, towards: side, isDirectory: false,
        left: action.left, right: action.right, isChecked: false, isRunnable: false,
        refusal: reason)
    }
  }

  private static func orphanOrAdd(
    _ path: String, entry: FileEntry, side: SyncAction.Side, tree: [String: FileEntry],
    kept: Set<String>, _ options: SyncOptions, _ removedFolders: inout [String]
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
    // Its visible contents still get their own rows; the folder stays for what's left in it.
    if kept.contains(path) { return nil }
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
