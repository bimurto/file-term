import Foundation

/// The macOS privacy settings FileTerm can send someone to.
public enum SystemPermission: String, Sendable {
  case fullDiskAccess, filesAndFolders, notifications

  public var title: String {
    switch self {
    case .fullDiskAccess: "Full Disk Access"
    case .filesAndFolders: "Files and Folders"
    case .notifications: "Notifications"
    }
  }

  public var settingsURL: URL {
    let base = "x-apple.systempreferences:"
    return switch self {
    case .fullDiskAccess: URL(string: base + "com.apple.preference.security?Privacy_AllFiles")!
    case .filesAndFolders:
      URL(string: base + "com.apple.preference.security?Privacy_FilesAndFolders")!
    case .notifications: URL(string: base + "com.apple.Notifications-Settings.extension")!
    }
  }

  /// Desktop, Documents, Downloads and other volumes have their own Files and Folders switch.
  /// Anything else that macOS protects needs Full Disk Access.
  public static func required(forPath path: String, home: String = NSHomeDirectory()) -> Self {
    let folders = ["Desktop", "Documents", "Downloads"].map { home + "/" + $0 } + ["/Volumes"]
    return folders.contains { path == $0 || path.hasPrefix($0 + "/") }
      ? .filesAndFolders : .fullDiskAccess
  }
}
