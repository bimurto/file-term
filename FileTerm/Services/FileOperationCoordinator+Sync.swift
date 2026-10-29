import AppKit
import FileTermCore

/// Runs the checked actions of a sync preview as M07 queue jobs (M09).
extension FileOperationCoordinator {
  /// One job per side that changes, so each job has one source and one destination.
  func submitSync(_ actions: [SyncAction], left: Location, right: Location) {
    let chosen = actions.filter { $0.isChecked && $0.isRunnable }
    guard !chosen.isEmpty else { return }
    let remoteDeletes = chosen.filter {
      $0.kind == .delete
        && $0.location(on: $0.towards, left: left, right: right).providerID != "local"
    }
    if !remoteDeletes.isEmpty {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Permanently delete \(remoteDeletes.count) remote items?"
      alert.informativeText =
        "Orphaned items on a remote location are deleted permanently and cannot be undone."
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Delete and Synchronize")
      guard alert.runModal() == .alertSecondButtonReturn else { return }
    }
    for side in [SyncAction.Side.right, .left] {
      let group = chosen.filter { $0.towards == side }
      if !group.isEmpty { submitSyncJob(group, towards: side, left: left, right: right) }
    }
  }

  private func submitSyncJob(
    _ group: [SyncAction], towards side: SyncAction.Side, left: Location, right: Location
  ) {
    let policy = preferences()
    transfers.preferences = policy
    let source = side == .right ? left : right
    let destination = side == .right ? right : left
    let sourceSide: SyncAction.Side = side == .right ? .left : .right
    let registry = registry
    let copies = group.filter { $0.kind != .delete && !$0.isDirectory }
    let total = copies.reduce(Int64(0)) { $0 + ($1.source?.size ?? 0) }
    let bothLocal = source.providerID == "local" && destination.providerID == "local"
    transfers.submit(
      kind: copies.isEmpty && !group.contains { $0.kind == .add } ? .delete : .copy,
      resources: Self.resources(for: [source, destination]), totalBytes: total,
      direction: Self.direction(from: [source], to: destination),
      sourceLabels: [describe(source)], destinationLabel: describe(destination)
    ) { control in
      let operations = LocalFileOperations()
      await operations.setTransferControl(control, verification: policy.verification)
      let transfer = ProviderTransfer(
        registry: registry, control: control, verification: policy.verification,
        log: { _ in }, resolve: { _ in ConflictResolution(decision: .replace) })
      @Sendable func provider(_ location: Location) throws -> any FileSystemProvider {
        guard let found = registry.provider(for: location.providerID) else {
          throw SyncError.missingProvider(location.providerID)
        }
        return found
      }
      do {
        let summary = try await SyncRunner.run(
          actions: group, control: control,
          makeFolder: { action in
            let folder = action.location(on: side, left: left, right: right)
            try await provider(folder).createDirectory(folder)
          },
          copy: { action in
            let from = action.location(on: sourceSide, left: left, right: right)
            let into = action.parentLocation(on: side, left: left, right: right)
            if bothLocal {
              // Local copies keep modification dates, so the next analysis comes out clean.
              _ = try await operations.transfer(
                sources: [URL(fileURLWithPath: from.path)],
                to: URL(fileURLWithPath: into.path), move: false,
                resolve: { _ in ConflictResolution(decision: .replace) })
            } else {
              _ = try await transfer.copy(sources: [from], to: into)
            }
          },
          delete: { action in
            let target = action.location(on: side, left: left, right: right)
            if target.providerID == "local" {
              _ = try await operations.trash(sources: [URL(fileURLWithPath: target.path)])
            } else {
              try await provider(target).delete(target)
            }
          })
        await self.refresh?()
        return summary
      } catch {
        await self.refresh?()
        throw error
      }
    }
  }
}
