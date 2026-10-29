import Foundation

/// Finds the preferences, caches and support folders an application leaves in ~/Library.
public enum AppLeftovers {
  public static var userLibrary: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
  }

  /// Existing items related to an app, sorted by path. Matching is by bundle identifier, with the
  /// app's name used only for the three folders apps commonly name after themselves.
  public static func relatedFiles(
    bundleID: String?, appName: String, library: URL = userLibrary
  ) -> [URL] {
    let fm = FileManager.default
    var found: [URL] = []
    func add(_ folder: String, _ name: String) {
      let url = library.appendingPathComponent(folder).appendingPathComponent(name)
      if (try? fm.attributesOfItem(atPath: url.path)) != nil { found.append(url) }
    }
    /// Children of a Library folder whose name passes `matches`.
    func addChildren(of folder: String, where matches: (String) -> Bool) {
      let directory = library.appendingPathComponent(folder)
      for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where matches(name) {
        found.append(directory.appendingPathComponent(name))
      }
    }
    if let id = bundleID, id.contains("."), !id.hasPrefix("."), !id.hasSuffix(".") {
      add("Preferences", id + ".plist")
      addChildren(of: "Preferences/ByHost") { $0.hasPrefix(id + ".") }
      for folder in [
        "Caches", "Application Support", "Containers", "HTTPStorages", "WebKit", "Logs",
      ] {
        add(folder, id)
      }
      add("HTTPStorages", id + ".binarycookies")
      add("Cookies", id + ".binarycookies")
      add("Saved Application State", id + ".savedState")
      addChildren(of: "Group Containers") {
        $0 == id || $0.hasSuffix("." + id) || $0.hasPrefix(id + ".")
      }
      addChildren(of: "LaunchAgents") { $0.hasPrefix(id + ".") }
    }
    if !appName.isEmpty, !appName.contains("/") {
      for folder in ["Application Support", "Caches", "Logs"] { add(folder, appName) }
    }
    var seen = Set<String>()
    return found.filter { seen.insert($0.path).inserted }
      .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }
}
