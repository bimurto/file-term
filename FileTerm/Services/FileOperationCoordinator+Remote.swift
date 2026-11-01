import AppKit
import FileTermCore

/// File commands for panes that show a remote provider (M08 T3b). Local panes keep the
/// `LocalFileOperations` paths in `FileOperationCoordinator`.
extension FileOperationCoordinator {
  /// One folder per launch, so quitting never removes what another running copy has open.
  static let downloadsFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("FileTerm-remote").appendingPathComponent(UUID().uuidString)

  /// Opened remote files are temporary copies. Only files opened with Commands › Edit are uploaded
  /// again, by `RemoteEditCoordinator`.
  static func removeTemporaryDownloads() {
    try? FileManager.default.removeItem(at: downloadsFolder)
  }

  func isRemote(_ pane: PaneModel) -> Bool {
    pane.location.map { $0.providerID != "local" } == true
  }

  /// Queues a remote edit under the server's resource key and refreshes the panes afterwards.
  @discardableResult
  func submitRemote(
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

  /// All items belong to the pane's connection. Swaps go through temporary names like local ones,
  /// and a failure puts the original names back.
  func submitRemoteBatchRename(_ renames: [(location: Location, name: String)]) {
    guard let providerID = renames.first?.location.providerID else { return }
    let registry = registry
    submitRemote(kind: .rename, locations: renames.map(\.location)) { control in
      try await RenameSequencer.perform(
        RenameSequencer.steps(for: renames.map { ($0.location.path, $0.name) }),
        before: { try await control.checkpoint() }
      ) { step in
        _ = try await ProviderItemOperations.rename(
          Location(providerID: providerID, path: step.path), to: step.name, registry: registry)
      }
      return TransferSummary(succeeded: renames.count)
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

  static func remoteDeleteAlert(itemCount: Int, from source: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Delete \(itemCount) item(s)?"
    alert.informativeText =
      "From: \(source)\nThis deletes them from the server and cannot be undone. "
      + "They will not go to your Mac’s Trash."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Delete")
    alert.buttons[1].hasDestructiveAction = true
    return alert
  }

  func deleteRemote(_ pane: PaneModel) {
    let entries = pane.selectedEntries
    guard let first = entries.first else { return }
    let alert = Self.remoteDeleteAlert(
      itemCount: entries.count, from: describe(first.location))
    guard alert.runModal() == .alertSecondButtonReturn else { return }
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
      if openArchive(entry, in: browser) { continue }
      submitRemote(
        kind: .open, locations: [entry.location], direction: .download, totalBytes: entry.size
      ) { control in
        guard let provider = registry.provider(for: entry.location.providerID) else {
          throw FileSystemError.unsupportedOperation
        }
        let file = try await Self.download(entry, provider: provider, control: control)
        if !NSWorkspace.shared.open(file) {
          throw FileSystemError.io("No application could open \(entry.name).")
        }
        return TransferSummary(succeeded: 1)
      }
    }
  }

  /// Copies a remote file into a fresh temporary folder and returns the copy.
  static func download(
    _ entry: FileEntry, provider: any FileSystemProvider, control: TransferControl
  ) async throws -> URL {
    guard FileName.isSafe(entry.name) else {
      throw FileSystemError.io("This item has an unsafe name, so it was not downloaded.")
    }
    let folder = downloadsFolder.appendingPathComponent(UUID().uuidString)
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
    return file
  }
}
