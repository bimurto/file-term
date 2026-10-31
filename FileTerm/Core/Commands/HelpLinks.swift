import Foundation

/// Where the online user guide explains the app and each of its commands.
public enum HelpLinks {
  private static let guide = "https://github.com/bimurto/file-term/blob/main/docs/user-guide/"

  public static let home = URL(string: guide + "README.md")!

  /// Commands the app generates, such as one per recent folder, share one entry in the reference.
  private static let families = [
    "go.recent.", "go.favorites.item.", "go.connections.open.", "go.connections.edit.",
    "go.connections.saved.", "go.connections.disconnect.", "go.workspaces.load.", "tools.run.",
    "commands.syncFavorite.", "file.openWith.", "commands.git.", "view.textEncoding.",
    "view.sort.", "view.group.", "window.tab", "file.copyPath.", "edit.text.", "file.iCloud.",
  ]

  public static func anchor(forCommand id: String) -> String {
    guard let family = families.first(where: { id.hasPrefix($0) }) else { return id }
    return family.hasSuffix(".") ? String(family.dropLast()) : family
  }

  public static func url(forCommand id: String) -> URL? {
    var components = URLComponents(string: guide + "commands.md")
    components?.fragment = anchor(forCommand: id)
    return components?.url
  }
}
