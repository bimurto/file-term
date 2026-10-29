import Foundation

/// Runs checked sync actions in a safe order: folders first, then files, then deletes (deepest
/// first). The work itself is supplied by closures so the order can be tested on its own.
public enum SyncRunner {
  public typealias Handler = @Sendable (SyncAction) async throws -> Void

  public static func run(
    actions: [SyncAction], control: TransferControl,
    makeFolder: @escaping Handler, copy: @escaping Handler, delete: @escaping Handler
  ) async throws -> TransferSummary {
    let chosen = actions.filter { $0.isChecked && $0.isRunnable }
    func depth(_ action: SyncAction) -> Int { action.relativePath.split(separator: "/").count }
    let folders = chosen.filter { $0.kind == .add && $0.isDirectory }
      .sorted { depth($0) < depth($1) }
    let files = chosen.filter { !$0.isDirectory && $0.kind != .delete }
    let deletes = chosen.filter { $0.kind == .delete }.sorted { depth($0) > depth($1) }
    var summary = TransferSummary()
    var failure: Error?
    for (group, handler) in [(folders, makeFolder), (files, copy), (deletes, delete)] {
      for action in group {
        try await control.checkpoint()
        do {
          try await handler(action)
          summary.succeeded += 1
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          summary.failed += 1
          failure = failure ?? error
        }
      }
    }
    if let failure, summary.succeeded > 0 {
      throw PartialTransferError(
        "\(summary.failed) of \(summary.succeeded + summary.failed) sync actions failed: "
          + failure.localizedDescription)
    }
    if let failure { throw failure }
    return summary
  }
}
