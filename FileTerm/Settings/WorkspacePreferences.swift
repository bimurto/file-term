import FileTermCore
import Foundation

struct WorkspacePreferences: Codable, Equatable {
  var restoreWindows = false
  var keepWindowsOnce = false
  var startingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
  var toolbarItems = [
    "go.back", "go.forward", "go.enclosingFolder", "go.connect", "group.layout",
    "group.viewMode", "go.syncBrowsing", "commands.sync", "go.toFolder", "go.favorites.manage",
    "file.openInTerminal", "file.trash", "view.preview", "view.activities", "view.logs",
    "view.terminal", "view.refresh", ToolbarLayout.flexibleSpace, "view.showHidden",
    ToolbarLayout.search,
  ]
  var sidebarOrder = ["devices", "recents", "tags"]

  /// A toolbar saved by an older version lacks newer default buttons. Each one not yet `offered`
  /// goes after the nearest default that comes before it, so buttons the user removed stay removed.
  /// Layout and view mode buttons saved one per command become their group first.
  mutating func addNewToolbarDefaults(offered: Set<String>) {
    toolbarItems = ToolbarLayout.items(from: toolbarItems)
    let offered = Set(offered.map(ToolbarLayout.itemID))
    let defaults = WorkspacePreferences().toolbarItems
    for (index, item) in defaults.enumerated()
    where !offered.contains(item) && !toolbarItems.contains(item) {
      let position = defaults[..<index].last { toolbarItems.contains($0) }
        .flatMap { toolbarItems.firstIndex(of: $0) }
      toolbarItems.insert(item, at: position.map { $0 + 1 } ?? 0)
    }
  }

  /// `sidebarOrder` saved by an older version lacks newer sections; they go at the end.
  var sidebarSections: [String] {
    sidebarOrder
      + ["devices", "recents", "tags", "iCloudDrive", "workspaces", "favorites"].filter {
        !sidebarOrder.contains($0)
      }
  }
}

struct WindowSnapshot: Codable {
  let browser: BrowserSnapshot
  let frame: String
  var terminal: TerminalPanelState? = nil
}

/// A named set of windows, with their tabs, panes and locations, that can be loaded later.
struct SavedWorkspace: Codable, Identifiable {
  var id = UUID()
  var name: String
  var windows: [WindowSnapshot]
}

struct ViewPreferenceSnapshot: Codable {
  let defaults: ViewOptions
  let folders: [Location: ViewOptions]
}

enum ToolbarSymbols {
  static func symbol(for id: String) -> String {
    switch id {
    case "go.back": "chevron.left"
    case "go.forward": "chevron.right"
    case "go.enclosingFolder": "arrow.up"
    case "view.single": "rectangle"
    case "view.vertical": "rectangle.split.2x1"
    case "view.horizontal": "rectangle.split.1x2"
    case "view.asIcons": "square.grid.2x2"
    case "view.asList": "list.bullet"
    case "view.asColumns": "rectangle.split.3x1"
    case "go.syncBrowsing": "link"
    case "commands.sync": "arrow.triangle.2.circlepath"
    case "go.toFolder": "folder.badge.gearshape"
    case "go.favorites.manage": "star"
    case "file.openInTerminal": "apple.terminal"
    case "file.trash": "trash"
    case "file.share": "square.and.arrow.up"
    case "go.connect": "point.topleft.down.to.point.bottomright.curvepath"
    case "view.preview": "sidebar.right"
    case "view.activities": "arrow.left.arrow.right"
    case "view.logs": "list.bullet.rectangle"
    case "view.terminal": "terminal"
    case "file.find": "magnifyingglass"
    case "view.showHidden": "eye"
    case "view.refresh": "arrow.clockwise"
    case "select.quick": "checkmark.circle"
    case "file.newTab": "plus.square"
    case "file.newWindow": "macwindow.badge.plus"
    case "view.clonePane": "plus.rectangle.on.rectangle"
    case "view.swapPanes": "arrow.left.arrow.right.square"
    case "commands.edit": "square.and.pencil"
    case "commands.compare": "arrow.left.and.right.square"
    case "commands.rename": "character.cursor.ibeam"
    case "file.getInfo": "info.circle"
    case "commands.compress": "archivebox"
    case "file.quickLook": "eye.circle"
    case "commands.copyTo": "doc.on.doc"
    case "commands.moveTo": "arrow.up.doc"
    case "file.newFolder": "folder.badge.plus"
    case "file.newFile": "doc.badge.plus"
    default: "command"
    }
  }
}
