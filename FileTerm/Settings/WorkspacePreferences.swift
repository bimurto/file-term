import FileTermCore
import Foundation

struct WorkspacePreferences: Codable, Equatable {
  var restoreWindows = false
  var keepWindowsOnce = false
  var startingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
  var toolbarItems = [
    "go.back", "go.forward", "go.enclosingFolder", "view.single", "view.vertical",
    "view.horizontal",
    "view.asIcons", "view.asList", "view.asColumns", "go.syncBrowsing", "go.toFolder",
    "view.preview", "view.activities", "view.logs", "view.refresh",
  ]
  var sidebarOrder = ["devices", "recents"]
}

struct WindowSnapshot: Codable {
  let browser: BrowserSnapshot
  let frame: String
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
    case "go.toFolder": "folder.badge.gearshape"
    case "view.preview": "sidebar.right"
    case "view.activities": "arrow.left.arrow.right"
    case "view.logs": "list.bullet.rectangle"
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
