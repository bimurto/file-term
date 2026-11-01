import FileTermCore
import Foundation

struct WorkspacePreferences: Codable, Equatable {
  var restoreWindows = false
  var keepWindowsOnce = false
  var startingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
  var toolbarItems = [
    "go.back", "go.forward", "go.enclosingFolder", "go.connect", "view.single", "view.vertical",
    "view.horizontal",
    "view.asIcons", "view.asList", "view.asColumns", "go.syncBrowsing", "commands.sync",
    "go.toFolder", "go.favorites.manage", "file.openInTerminal", "file.trash",
    "view.preview", "view.activities", "view.logs", "view.terminal", "view.refresh",
  ]
  var sidebarOrder = ["devices", "recents", "tags"]

  /// A toolbar saved by an older version lacks newer default buttons. Each one not yet `offered`
  /// goes after the nearest default that comes before it, so buttons the user removed stay removed.
  mutating func addNewToolbarDefaults(offered: Set<String>) {
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
    case "go.connect": "network"
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
    default: "command"
    }
  }
}
