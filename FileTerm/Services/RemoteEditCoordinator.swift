import AppKit
import FileTermCore

/// Edits a remote file in a local editor: downloads a temporary copy, watches it, and uploads it
/// again on every save once the user has confirmed the account and path.
@MainActor final class RemoteEditCoordinator {
  /// What a local file looked like when it was last uploaded or attempted.
  struct Stamp: Equatable {
    let modified: Date
    let size: Int64

    init(modified: Date, size: Int64) {
      self.modified = modified
      self.size = size
    }

    /// Reads the file system directly. `URL.resourceValues` caches inside the URL, so it keeps
    /// reporting the old size and date after the file is saved.
    init?(url: URL) {
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let modified = attributes[.modificationDate] as? Date,
        let size = attributes[.size] as? NSNumber
      else { return nil }
      self.init(modified: modified, size: size.int64Value)
    }
  }

  @MainActor final class Session {
    let remote: Location
    let local: URL
    var lastAttempt: Stamp
    var confirmed = false
    var isConfirming = false
    var isStopped = false
    let notify: (String) -> Void
    let watcher = FolderWatcher()

    init(remote: Location, local: URL, lastAttempt: Stamp, notify: @escaping (String) -> Void) {
      self.remote = remote
      self.local = local
      self.lastAttempt = lastAttempt
      self.notify = notify
    }
  }

  @MainActor private final class JobReference { var id: UUID? }

  private let fileOperations: FileOperationCoordinator
  private let confirm: (_ target: String, _ name: String) async -> Bool
  private let openFile: (_ file: URL, _ editors: [EditorMapping]) async -> String?
  private(set) var sessions: [Session] = []

  init(
    fileOperations: FileOperationCoordinator,
    confirm: @escaping (_ target: String, _ name: String) async -> Bool = RemoteEditCoordinator
      .askUser,
    openFile: ((_ file: URL, _ editors: [EditorMapping]) async -> String?)? = nil
  ) {
    self.fileOperations = fileOperations
    self.confirm = confirm
    self.openFile =
      openFile ?? { [unowned fileOperations] file, editors in
        await fileOperations.openInEditor(file, editors: editors)
      }
  }

  /// Asks once per edited file, before the first upload, which account and path will be written.
  static func askUser(target: String, name: String) async -> Bool {
    let alert = NSAlert()
    alert.messageText = "Upload your changes to “\(name)”?"
    alert.informativeText =
      "Account and path:\n\(target)\n\nEvery time you save, the file on the server is replaced "
      + "until you quit FileTerm or the connection closes."
    alert.addButton(withTitle: "Upload")
    alert.addButton(withTitle: "Stop Watching")
    return alert.runModal() == .alertFirstButtonReturn
  }

  /// Downloads the file, opens it in the mapped editor and starts watching it. Editing a file that
  /// is already being edited reopens the existing copy, so unsaved local work is never replaced.
  @discardableResult
  func edit(_ entry: FileEntry, editors: [EditorMapping], notify: @escaping (String) -> Void)
    -> UUID?
  {
    if let existing = sessions.first(where: { $0.remote == entry.location }) {
      reopen(existing, editors: editors)
      return nil
    }
    guard let provider = fileOperations.registry.provider(for: entry.location.providerID) else {
      notify("The connection for “\(entry.name)” is not open.")
      return nil
    }
    return fileOperations.submitRemote(
      kind: .open, locations: [entry.location], direction: .download, totalBytes: entry.size
    ) { [weak self] control in
      let file = try await FileOperationCoordinator.download(
        entry, provider: provider, control: control)
      self?.begin(entry.location, file: file, editors: editors, notify: notify)
      return TransferSummary(succeeded: 1)
    }
  }

  private func begin(
    _ remote: Location, file: URL, editors: [EditorMapping], notify: @escaping (String) -> Void
  ) {
    guard let stamp = Stamp(url: file) else { return }
    let session = Session(remote: remote, local: file, lastAttempt: stamp, notify: notify)
    session.watcher.onChange = { [weak self, weak session] _ in
      guard let self, let session else { return }
      Task { await self.check(session) }
    }
    session.watcher.watch([Self.realPath(of: file.deletingLastPathComponent())])
    sessions.append(session)
    reopen(session, editors: editors)
  }

  /// FSEvents reports resolved paths (`/private/var/...`), and `FolderWatcher` matches them by text,
  /// so the temporary folder must be handed over resolved. Foundation keeps `/var` as it is.
  private static func realPath(of url: URL) -> String {
    url.path.withCString { path in
      guard let resolved = realpath(path, nil) else { return url.path }
      defer { free(resolved) }
      return String(cString: resolved)
    }
  }

  private func reopen(_ session: Session, editors: [EditorMapping]) {
    Task {
      if let message = await openFile(session.local, editors) { session.notify(message) }
    }
  }

  /// Uploads the file if it changed since the last attempt. Called for every file system event.
  func check(_ session: Session) async {
    guard !session.isStopped, !session.isConfirming,
      var stamp = Stamp(url: session.local), stamp != session.lastAttempt
    else { return }
    let name = session.local.lastPathComponent
    guard fileOperations.registry.provider(for: session.remote.providerID) != nil else {
      stop(session, "The connection closed, so “\(name)” is no longer uploaded when saved.")
      return
    }
    if !session.confirmed {
      session.isConfirming = true
      let approved = await confirm(fileOperations.describe(session.remote), name)
      session.isConfirming = false
      guard approved else {
        stop(session, "Stopped watching “\(name)”. Your changes were not uploaded.")
        return
      }
      session.confirmed = true
      // Saves made while the question was open belong in this upload.
      stamp = Stamp(url: session.local) ?? stamp
    }
    session.lastAttempt = stamp
    upload(session, size: stamp.size)
  }

  func stop(_ session: Session, _ message: String? = nil) {
    session.isStopped = true
    session.watcher.watch([])
    sessions.removeAll { $0 === session }
    if let message { session.notify(message) }
  }

  private func upload(_ session: Session, size: Int64) {
    let remote = session.remote
    let name = (remote.path as NSString).lastPathComponent
    let folder = Location(
      providerID: remote.providerID, path: (remote.path as NSString).deletingLastPathComponent)
    let source = Location(providerID: "local", path: session.local.path)
    let queue = fileOperations.transfers
    let registry = fileOperations.registry
    let policy = fileOperations.preferences()
    let describe = fileOperations.describe
    let reference = JobReference()
    queue.preferences = policy
    let id = queue.submit(
      kind: .upload, resources: FileOperationCoordinator.resources(for: [remote]),
      totalBytes: size, direction: .upload, sourceLabels: [session.local.lastPathComponent],
      destinationLabel: describe(remote)
    ) { [weak self] control in
      let transfer = ProviderTransfer(
        registry: registry, control: control, verification: policy.verification,
        log: { message in
          Task { @MainActor in if let id = reference.id { queue.log(id, message) } }
        },
        resolve: { _ in ConflictResolution(decision: .replace) })
      do {
        let summary = try await transfer.copy(sources: [source], to: folder, newName: name)
        if let id = reference.id { queue.log(id, "Uploaded \(name) to \(describe(remote))") }
        await self?.fileOperations.refresh?()
        return summary
      } catch {
        if let id = reference.id { queue.log(id, "Upload of \(name) failed: \(error)") }
        throw error
      }
    }
    reference.id = id
  }
}
