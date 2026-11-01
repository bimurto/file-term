/// The order of each menu bar menu, in groups with a separator between them. Only menus are
/// arranged this way: `CommandRegistry.commands` keeps its order for everything else.
public enum MenuLayout {
  public enum Row: Equatable, Sendable {
    case item
    case hiddenItem
    case separator
  }

  /// A group's entries are command IDs, submenu titles, or ID prefixes ending in `.` or `tab`.
  private static let groups: [[String]: [[String]]] = [
    ["FileTerm"]: [
      ["app.about", "app.checkForUpdates"], ["app.settings"], ["app.emptyTrash"],
      ["app.hide", "app.quit", "app.quitKeepWindows"],
    ],
    ["File"]: [
      [
        "file.newWindow", "file.newTab", "file.newFolder", "file.newFolderWithSelection",
        "file.newFile",
      ],
      [
        "file.open", "file.openInNewTab", "file.openInNewWindow", "Open With",
        "file.openInTerminal", "file.packageContents",
      ],
      [
        "file.getInfo", "file.share", "file.tags", "Tags", "file.quickLook",
        "file.revealInFinder", "file.slideshow", "file.print",
      ],
      ["Copy Path", "file.copyURL", "file.openURL", "file.copyDropboxLink", "iCloud"],
      ["file.makeAlias", "file.makeAliasTo", "file.makeSymlink", "file.makeSymlinkTo"],
      ["file.find", "file.closeSearch"],
      ["file.eject"],
      ["file.closeTab", "file.closeOtherTabs", "file.close"],
    ],
    ["Edit"]: [
      ["edit.undo", "edit.redo"],
      ["edit.text.cut", "edit.text.copy", "edit.text.paste", "edit.moveItemsHere"],
      ["edit.selectAll", "edit.deselectAll", "edit.invertSelection", "select.quick"],
    ],
    ["View"]: [
      ["view.preview", "view.activities", "view.logs"],
      [
        "view.twoPanes", "view.swapPanes", "view.clonePane", "view.single", "view.vertical",
        "view.horizontal",
      ],
      ["view.asIcons", "view.asList", "view.asColumns"],
      ["Sort by", "Group by", "view.options"],
      [
        "view.pathBar", "view.titleBar", "view.toolbar", "view.sidebar", "view.tabBar",
        "view.devices", "view.deviceInfo", "view.recentFolders", "view.tags", "view.workspaces",
        "view.iCloudDrive", "view.favorites",
      ],
      [
        "view.customizeToolbar", "view.sidebarEditor", "view.saveDefaults",
        "view.restoreDefaults",
      ],
      ["view.showHidden", "view.refresh", "view.autoRefresh"],
      ["view.terminal", "Terminal"],
      ["Text Encoding"],
    ],
    ["View", "Terminal"]: [
      ["terminal.focus"],
      [
        "terminal.link", "terminal.followActive", "terminal.followFirst", "terminal.followSecond",
        "terminal.reverseSync", "terminal.sync", "terminal.reveal",
      ],
      ["terminal.insertSelection", "terminal.openSSH"],
      ["terminal.clear", "terminal.find"],
      ["terminal.dock", "terminal.close"],
    ],
    ["Go"]: [
      [
        "go.back", "go.forward", "go.enclosingFolder", "go.toFolder", "quickOpen",
        "go.syncBrowsing",
      ],
      [
        "go.home", "go.desktop", "go.documents", "go.downloads", "go.library", "go.applications",
        "go.utilities",
      ],
      ["go.connect", "Connections", "go.favorites.manage", "Favorites"],
      ["Recent Folders", "Workspaces"],
    ],
    ["Commands"]: [
      ["commands.edit", "commands.rename", "commands.duplicate"],
      ["commands.copyTo", "commands.copyToAs", "commands.moveTo"],
      [
        "commands.compress", "commands.compressOptions", "commands.extract",
        "commands.extractTo",
      ],
      ["file.trash", "commands.delete", "commands.appCleanup"],
      ["commands.compare", "commands.checksum", "commands.folderSizes"],
      ["commands.sync", "Sync Favorites"],
      ["Source Control"],
      ["commands.manageTools", "Tools"],
    ],
    ["Window"]: [
      ["window.minimize", "window.zoom"],
      [
        "window.pinView", "window.moveTabToOtherPane", "window.previousTab", "window.nextTab",
        "window.tab",
      ],
      ["window.bringAll"],
    ],
  ]

  private static func matches(_ key: String, entry: String) -> Bool {
    if key == entry { return true }
    // `window.tab` covers `window.tab1` to `window.tab5`.
    return entry == "window.tab" && key.hasPrefix(entry)
      && key.dropFirst(entry.count).allSatisfy(\.isNumber)
  }

  /// Whether the table places this command ID or submenu title in the menu at `path`.
  public static func isListed(_ key: String, in path: [String]) -> Bool {
    guard let groups = groups[path] else { return true }
    return groups.joined().contains { matches(key, entry: $0) }
  }

  /// Sorts `keys`, given in registry order, into groups, returned as indices into `keys`. Anything
  /// the table doesn't list goes in a final group, so a new command can't get lost.
  public static func arrange(_ keys: [String], in path: [String]) -> [[Int]] {
    guard let groups = groups[path] else { return keys.isEmpty ? [] : [Array(keys.indices)] }
    var arranged = Array(repeating: [(position: Int, index: Int)](), count: groups.count + 1)
    for (index, key) in keys.enumerated() {
      var placed = false
      for (group, entries) in groups.enumerated() {
        if let position = entries.firstIndex(where: { matches(key, entry: $0) }) {
          arranged[group].append((position, index))
          placed = true
          break
        }
      }
      if !placed { arranged[groups.count].append((keys.count, index)) }
    }
    return arranged.filter { !$0.isEmpty }.map { group in
      group.sorted { ($0.position, $0.index) < ($1.position, $1.index) }.map(\.index)
    }
  }

  /// The separators to hide: those first, last or next to another among the visible rows.
  public static func separatorsToHide(_ rows: [Row]) -> Set<Int> {
    var hidden: Set<Int> = []
    var lastVisibleIsItem = false
    var pending: Int?
    for (index, row) in rows.enumerated() {
      switch row {
      case .hiddenItem: continue
      case .item:
        lastVisibleIsItem = true
        pending = nil
      case .separator:
        if lastVisibleIsItem {
          lastVisibleIsItem = false
          pending = index
        } else {
          hidden.insert(index)
        }
      }
    }
    if let pending { hidden.insert(pending) }
    return hidden
  }
}
