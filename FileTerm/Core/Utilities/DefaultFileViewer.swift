import Foundation

/// The system-wide `NSFileViewer` default, which decides the app that handles Reveal and Show in
/// Finder requests. It is the same value as `defaults write -g NSFileViewer`.
public struct DefaultFileViewer: Sendable {
  private let read: @Sendable () -> String?
  private let write: @Sendable (String?) -> Void

  public init(
    read: @escaping @Sendable () -> String?, write: @escaping @Sendable (String?) -> Void
  ) {
    self.read = read
    self.write = write
  }

  public static let system = DefaultFileViewer(
    read: {
      CFPreferencesCopyValue(
        "NSFileViewer" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost) as? String
    },
    write: { value in
      CFPreferencesSetValue(
        "NSFileViewer" as CFString, value as CFString?, kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      CFPreferencesSynchronize(
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    })

  public func isDefault(_ bundleID: String) -> Bool { read() == bundleID }

  /// Returns the viewer that was set before, so `revert` can put it back.
  public func enable(_ bundleID: String) -> String? {
    let previous = read()
    write(bundleID)
    return previous == bundleID ? nil : previous
  }

  /// Restores `previous`, or clears the value so Finder is the viewer again. Does nothing when
  /// another app has taken over since.
  public func revert(_ bundleID: String, to previous: String?) {
    if isDefault(bundleID) { write(previous) }
  }
}

/// The folders to show for an open or reveal request.
public struct RevealRequest: Equatable, Sendable {
  public let folder: String
  public let selected: [String]

  public init(folder: String, selected: [String]) {
    self.folder = folder
    self.selected = selected
  }

  /// A folder opens as itself. Files open their enclosing folder with them selected, and files
  /// in the same folder share a request.
  public static func plan(paths: [String], isDirectory: (String) -> Bool) -> [RevealRequest] {
    var result: [RevealRequest] = []
    for path in paths {
      let folder = isDirectory(path) ? path : (path as NSString).deletingLastPathComponent
      let selected = isDirectory(path) ? [] : [path]
      if let index = result.firstIndex(where: { $0.folder == folder }) {
        result[index] = RevealRequest(folder: folder, selected: result[index].selected + selected)
      } else {
        result.append(RevealRequest(folder: folder, selected: selected))
      }
    }
    return result
  }
}
