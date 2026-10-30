import Foundation

/// Decides what a file drop onto a folder does.
public enum FileDrop {
  /// Leaves out items already in the folder, and folders dropped onto themselves or their contents.
  public static func sources(_ paths: [String], into destination: String) -> [String] {
    paths.filter { path in
      (path as NSString).deletingLastPathComponent != destination
        && destination != path && !destination.hasPrefix(path + "/")
    }
  }

  /// Follows Finder: the same volume moves and another volume copies. Option always copies.
  public static func movesByDefault(sameVolume: Bool, optionPressed: Bool) -> Bool {
    sameVolume && !optionPressed
  }
}
