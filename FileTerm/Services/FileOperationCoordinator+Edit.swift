import AppKit
import FileTermCore

extension FileOperationCoordinator {
  /// Opens a local file in the editor mapped to its extension (Settings › Editing), or in its
  /// default application when none is mapped. Returns a message when something went wrong.
  @discardableResult
  func openInEditor(_ url: URL, editors: [EditorMapping]) async -> String? {
    let name = url.lastPathComponent
    guard let mapping = EditorMapping.mapping(for: name, in: editors) else {
      return NSWorkspace.shared.open(url) ? nil : "Could not open \(name)."
    }
    guard FileManager.default.fileExists(atPath: mapping.applicationPath) else {
      let opened = NSWorkspace.shared.open(url)
      return "\(mapping.displayName) was not found."
        + (opened ? " Opened \(name) with the default application." : " Could not open \(name).")
    }
    do {
      _ = try await NSWorkspace.shared.open(
        [url], withApplicationAt: URL(fileURLWithPath: mapping.applicationPath),
        configuration: NSWorkspace.OpenConfiguration())
      return nil
    } catch {
      return "Could not open \(name) in \(mapping.displayName): \(error.localizedDescription)"
    }
  }
}
