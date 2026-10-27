import AppKit
import FileTermCore

/// File commands for panes that show a remote provider (M08 T3b). Local panes keep the
/// `LocalFileOperations` paths in `FileOperationCoordinator`.
extension FileOperationCoordinator {
  static let downloadsFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("FileTerm-remote")

  /// Opened remote files are temporary copies; edits are not uploaded back.
  static func removeTemporaryDownloads() {
    try? FileManager.default.removeItem(at: downloadsFolder)
  }

  func isRemote(_ pane: PaneModel) -> Bool {
    pane.location.map { $0.providerID != "local" } == true
  }

  /// Queues a remote edit under the server's resource key and refreshes the panes afterwards.
  @discardableResult
  private func submitRemote(
    kind: TransferJobKind, locations: [Location], destination: Location? = nil,
    direction: TransferDirection = .local, totalBytes: Int64? = nil,
    action: @escaping @MainActor (TransferControl) async throws -> TransferSummary
  ) -> UUID {
    transfers.preferences = preferences()
    return transfers.submit(
      kind: kind, resources: Self.resources(for: locations + [destination].compactMap { $0 }),
      totalBytes: totalBytes, direction: direction, sourceLabels: locations.map(describe),
      destinationLabel: destination.map(describe)
    ) { control in
      do {
        let summary = try await action(control)
        await self.refresh?()
        return summary
      } catch {
        await self.refresh?()
        throw error
      }
    }
  }

  func bindRemoteRename(_ pane: PaneModel) {
    pane.onRename = { [weak self, weak pane] location, name in
      guard let self, let pane else { return }
      let isFile = pane.entries.first { $0.location == location }?.kind == .file
      if isFile,
        (location.path as NSString).pathExtension != (name as NSString).pathExtension
      {
        let alert = NSAlert()
        alert.messageText = "Change the filename extension?"
        alert.informativeText =
          "Changing the extension may cause the file to open in a different application."
        alert.addButton(withTitle: "Change Extension")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
      }
      let registry = registry
      submitRemote(kind: .rename, locations: [location]) { _ in
        let renamed = try await ProviderItemOperations.rename(
          location, to: name, registry: registry)
        if pane.location == location.parent { pane.selection = [renamed] }
        return TransferSummary(succeeded: 1)
      }
    }
  }

  func createRemoteFolder(_ pane: PaneModel) {
    guard let folder = pane.location else { return }
    bindRemoteRename(pane)
    let registry = registry
    submitRemote(kind: .create, locations: [folder]) { _ in
      let created = try await ProviderItemOperations.createFolder(in: folder, registry: registry)
      await self.refresh?()
      if pane.location == folder {
        pane.selection = [created]
        pane.renamingLocation = created
      }
      return TransferSummary(succeeded: 1)
    }
  }

  func deleteRemote(_ pane: PaneModel) {
    let entries = pane.selectedEntries
    guard let first = entries.first else { return }
    let alert = NSAlert()
    alert.messageText = "Delete \(entries.count) item(s)?"
    alert.informativeText =
      "From: \(describe(first.location))\nThis deletes them from the server and cannot be undone."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let registry = registry
    submitRemote(kind: .delete, locations: entries.map(\.location)) { control in
      var summary = TransferSummary()
      for entry in entries {
        try await control.checkpoint()
        guard let provider = registry.provider(for: entry.location.providerID) else {
          throw FileSystemError.unsupportedOperation
        }
        do { try await provider.delete(entry.location) } catch {
          if summary.succeeded == 0 { throw error }
          throw FileSystemError.io(
            "Deleted \(summary.succeeded) of \(entries.count) items. "
              + "\(entry.name): \(error.localizedDescription)")
        }
        summary.succeeded += 1
      }
      return summary
    }
  }

  /// Downloads each selected file to a temporary folder and opens it. Folders are entered.
  func openRemote(_ browser: BrowserModel) {
    let paneID = browser.activePaneID
    let entries = browser.activePane.selectedEntries
    if let folder = entries.first(where: { $0.kind == .directory }) {
      Task { await browser.enterFolder(folder.location, in: paneID) }
      return
    }
    let registry = registry
    for entry in entries where entry.kind == .file {
      submitRemote(
        kind: .open, locations: [entry.location], direction: .download, totalBytes: entry.size
      ) { control in
        guard let provider = registry.provider(for: entry.location.providerID) else {
          throw FileSystemError.unsupportedOperation
        }
        let folder = Self.downloadsFolder.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(entry.name)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        do {
          let reader = try await provider.read(entry.location)
          while let chunk = try await reader.next() {
            try await control.advance(bytes: Int64(chunk.count))
            try handle.write(contentsOf: chunk)
          }
          try handle.close()
        } catch {
          try? handle.close()
          try? FileManager.default.removeItem(at: folder)
          throw error
        }
        if !NSWorkspace.shared.open(file) {
          throw FileSystemError.io("No application could open \(entry.name).")
        }
        return TransferSummary(succeeded: 1)
      }
    }
  }
}
