import AppKit
import FileTermCore

/// Permanent deletion and Empty Trash (M10.05, M10.04). Move to Trash lives in the main file
/// because it is undoable and shares the local-operation job path.
extension FileOperationCoordinator {
  /// Commands › Delete…: asks, then removes local items for good. Remote items go through the
  /// server delete, which has its own confirmation.
  func deletePermanently(_ pane: PaneModel, window: NSWindow?) {
    if rejectsArchiveEdit(pane) { return }
    if isRemote(pane) { return deleteRemote(pane) }
    let sources = localURLs(pane)
    guard !sources.isEmpty else { return }
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText =
      sources.count == 1
      ? "Permanently delete “\(sources[0].lastPathComponent)”?"
      : "Permanently delete \(sources.count) items?"
    alert.informativeText =
      "This deletion is permanent and cannot be undone. "
      + "The items will not be moved to the Trash."
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Delete Permanently")
    alert.buttons[1].hasDestructiveAction = true
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    run(kind: .delete, sources: sources, pane: pane, window: window) { operations in
      try await operations.deletePermanently(sources: sources)
      return []
    }
  }

  /// Items in the user's Trash, or nil when it cannot be read (macOS may withhold access).
  func trashItemCount() -> Int? {
    guard
      let trash = try? FileManager.default.url(
        for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
      let names = try? FileManager.default.contentsOfDirectory(atPath: trash.path)
    else { return nil }
    return names.filter { $0 != ".DS_Store" }.count
  }

  /// FileTerm › Empty Trash…: a separate, confirmed command. Finder does the emptying so every
  /// volume's Trash is covered.
  func emptyTrash() {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Empty the Trash?"
    alert.informativeText =
      (trashItemCount().map { "\($0) item(s) in the Trash will be deleted. " }
        ?? "Everything in the Trash will be deleted. ") + "This cannot be undone."
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Empty Trash")
    alert.buttons[1].hasDestructiveAction = true
    guard alert.runModal() == .alertSecondButtonReturn else { return }
    Task {
      let failure = await Task.detached { () -> String? in
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty the trash")?
          .executeAndReturnError(&error)
        return error.map {
          ($0[NSAppleScript.errorMessage] as? String) ?? "Finder could not empty the Trash."
        }
      }.value
      if let failure {
        let alert = NSAlert()
        alert.messageText = "Could not empty the Trash"
        alert.informativeText = failure
        alert.runModal()
      }
    }
  }
}
