import CryptoKit
import Darwin
import Foundation

public enum ConflictDecision: Sendable {
  case replace, replaceOlder, keepBoth, skip, stop, merge
}

public struct ConflictResolution: Sendable {
  public let decision: ConflictDecision
  public let applyToAll: Bool
  public init(decision: ConflictDecision, applyToAll: Bool = false) {
    self.decision = decision
    self.applyToAll = applyToAll
  }
}

public struct FileConflict: Sendable {
  public let source: URL
  public let destination: URL
  public let isDirectoryMerge: Bool
  public init(source: URL, destination: URL, isDirectoryMerge: Bool) {
    self.source = source
    self.destination = destination
    self.isDirectoryMerge = isDirectoryMerge
  }
}

public typealias ConflictResolver = @Sendable (FileConflict) async -> ConflictResolution

public struct FileOperationHistoryState: Sendable {
  public let canUndo: Bool
  public let canRedo: Bool
  public let undoReason: String?
  public let redoReason: String?
}

public enum LocalFileOperationError: Error, LocalizedError, Sendable {
  case invalidName, nonLocalURL, destinationExists, unsafeTransfer, invalidMerge
  case changedContents, nothingToUndo, nothingToRedo, operationInProgress

  public var errorDescription: String? {
    switch self {
    case .invalidName: return "Enter a valid file name without slashes or null characters."
    case .nonLocalURL: return "This operation requires a local file URL."
    case .destinationExists:
      return "An item already exists at the destination. Nothing was overwritten."
    case .unsafeTransfer: return "An item cannot be transferred onto itself or into its own folder."
    case .invalidMerge: return "Only two folders can be merged."
    case .changedContents:
      return "Files have changed since this operation. Your changes were preserved."
    case .nothingToUndo: return "There is nothing to undo."
    case .nothingToRedo: return "There is nothing to redo."
    case .operationInProgress: return "Wait for the current file operation to finish."
    }
  }
}

/// Local, non-overwriting operations with in-memory, reversible history.
/// History storage is intentionally retained on disk, including after this actor is released.
/// Filesystem access by other processes is not locked; guards are best-effort checks, not transactions.
public actor LocalFileOperations {
  private let fm = FileManager.default
  private var busy = false
  private var undoStack: [Transaction] = []
  private var redoStack: [Transaction] = []

  private struct Step {
    let from: URL
    let to: URL
    let signature: Signature
  }
  private struct Transaction {
    var steps: [Step] = []
    var cursor = 0
  }
  private indirect enum Signature: Equatable {
    case file(Data, Date?, UInt?)
    case directory([String: Signature])
    case link(String)
  }
  private struct TransferContext {
    var transaction = Transaction()
    var all: ConflictDecision?
    var stopped = false
  }

  private let renameItem: @Sendable (URL, URL) throws -> Void
  private let removeItem: @Sendable (URL) throws -> Void

  public init() {
    renameItem = { try Self.exclusiveRename($0, $1) }
    removeItem = { try FileManager.default.removeItem(at: $0) }
  }

  // Internal syscall seams allow deterministic EXDEV/deletion-failure tests without mounts.
  init(
    rename: @escaping @Sendable (URL, URL) throws -> Void,
    remove: @escaping @Sendable (URL) throws -> Void
  ) {
    renameItem = rename
    removeItem = remove
  }

  public func create(in parent: URL, name: String, directory: Bool) throws -> URL {
    try begin()
    defer { busy = false }
    try validate(name)
    try local(parent)
    let requested = canonical(parent).appendingPathComponent(name)
    let destination = exists(requested) ? unique(requested) : requested
    var transaction = Transaction()
    defer { commit(transaction) }
    let staged = try storageURL()
    if directory {
      try fm.createDirectory(at: staged, withIntermediateDirectories: false)
    } else {
      try Data().write(to: staged, options: .withoutOverwriting)
    }
    try recordMove(staged, destination, in: &transaction)
    return destination
  }

  /// Creates a uniquely named folder and moves the selection into it as one history unit.
  /// If a later item fails, the folder and earlier completed moves remain undoable together.
  public func createWithSelection(
    in parent: URL, name: String, sources: [URL],
    resolve: @escaping ConflictResolver = { _ in ConflictResolution(decision: .skip) }
  ) async throws -> URL {
    try begin()
    defer { busy = false }
    try local(parent)
    try validate(name)
    let requested = canonical(parent).appendingPathComponent(name)
    let destination = exists(requested) ? unique(requested) : requested
    // Validate before creating the destination, particularly for selected ancestor folders.
    for source in sources {
      try local(source)
      try safe(source, destination.appendingPathComponent(source.lastPathComponent))
    }
    var context = TransferContext()
    defer { commit(context.transaction) }
    let staged = try storageURL()
    try fm.createDirectory(at: staged, withIntermediateDirectories: false)
    try recordMove(staged, destination, in: &context.transaction)
    for source in sources {
      if context.stopped { break }
      _ = try await transferOne(
        source: source, destination: destination.appendingPathComponent(source.lastPathComponent),
        move: true, context: &context, resolve: resolve)
    }
    return destination
  }

  public func transfer(
    sources: [URL], to parent: URL, move: Bool, newName: String? = nil,
    resolve: @escaping ConflictResolver = { _ in ConflictResolution(decision: .skip) }
  ) async throws -> [URL] {
    try begin()
    defer { busy = false }
    try local(parent)
    if let newName {
      try validate(newName)
      guard sources.count == 1 else { throw LocalFileOperationError.invalidName }
    }
    var context = TransferContext()
    defer { commit(context.transaction) }
    var results: [URL] = []
    for source in sources {
      if context.stopped { break }
      let destination = canonical(parent).appendingPathComponent(
        newName ?? source.lastPathComponent)
      if let result = try await transferOne(
        source: source, destination: destination, move: move, context: &context, resolve: resolve)
      {
        results.append(result)
      }
    }
    return results
  }

  public func duplicate(sources: [URL]) throws -> [URL] {
    try begin()
    defer { busy = false }
    var transaction = Transaction()
    defer { commit(transaction) }
    var results: [URL] = []
    for source in sources {
      try local(source)
      let destination = unique(canonical(source))
      try copy(source, to: destination, in: &transaction)
      results.append(destination)
    }
    return results
  }

  public func rename(source: URL, name: String) throws -> URL {
    try begin()
    defer { busy = false }
    try validate(name)
    try local(source)
    let source = canonical(source)
    let destination = source.deletingLastPathComponent().appendingPathComponent(name)
    if source.path == destination.path {
      _ = try signature(source)
      return source
    }
    try safe(source, destination)
    var transaction = Transaction()
    defer { commit(transaction) }
    try recordMove(source, destination, in: &transaction)
    return destination
  }

  #if os(macOS)
    /// Uses the native Trash and records its actual resulting URLs for guarded restoration.
    /// Emptying Trash externally disables undo for those items; no private recovery copy is kept.
    public func trash(sources: [URL]) throws -> [URL] {
      try begin()
      defer { busy = false }
      var transaction = Transaction()
      defer { commit(transaction) }
      var results: [URL] = []
      for source in sources {
        try local(source)
        let source = canonical(source)
        let fingerprint = try signature(source)
        var resulting: NSURL?
        try fm.trashItem(at: source, resultingItemURL: &resulting)
        guard let destination = resulting as URL? else {
          throw CocoaError(.fileWriteUnknown)
        }
        transaction.steps.append(Step(from: source, to: destination, signature: fingerprint))
        transaction.cursor += 1
        results.append(destination)
      }
      return results
    }
  #endif

  public func undo() throws {
    try begin()
    defer { busy = false }
    guard var transaction = undoStack.popLast() else { throw LocalFileOperationError.nothingToUndo }
    do {
      while transaction.cursor > 0 {
        let step = transaction.steps[transaction.cursor - 1]
        try guardedMove(step.to, step.from, signature: step.signature)
        transaction.cursor -= 1
      }
      redoStack.append(transaction)
    } catch {
      undoStack.append(transaction)
      throw error
    }
  }

  public func redo() throws {
    try begin()
    defer { busy = false }
    guard var transaction = redoStack.popLast() else { throw LocalFileOperationError.nothingToRedo }
    do {
      while transaction.cursor < transaction.steps.count {
        let step = transaction.steps[transaction.cursor]
        try guardedMove(step.from, step.to, signature: step.signature)
        transaction.cursor += 1
      }
      undoStack.append(transaction)
    } catch {
      redoStack.append(transaction)
      throw error
    }
  }

  public func historyState() -> FileOperationHistoryState {
    let undoReason = reason(undoStack.last, undo: true)
    let redoReason = reason(redoStack.last, undo: false)
    return FileOperationHistoryState(
      canUndo: undoReason == nil, canRedo: redoReason == nil,
      undoReason: undoReason, redoReason: redoReason)
  }

  private func begin() throws {
    guard !busy else { throw LocalFileOperationError.operationInProgress }
    busy = true
  }

  private func commit(_ transaction: Transaction) {
    guard !transaction.steps.isEmpty else { return }
    undoStack.append(transaction)
    redoStack.removeAll()
  }

  private func reason(_ transaction: Transaction?, undo: Bool) -> String? {
    if busy { return "Another operation is in progress." }
    guard let transaction else { return undo ? "Nothing to undo." : "Nothing to redo." }
    let index = undo ? transaction.cursor - 1 : transaction.cursor
    guard transaction.steps.indices.contains(index) else { return "No remaining steps." }
    let step = transaction.steps[index]
    do {
      try check(undo ? step.to : step.from, undo ? step.from : step.to, signature: step.signature)
      return nil
    } catch { return "Files have changed or are inaccessible: \(error)" }
  }

  private func transferOne(
    source: URL, destination: URL, move: Bool, context: inout TransferContext,
    resolve: ConflictResolver
  ) async throws -> URL? {
    try local(source)
    try local(destination)
    let source = canonical(source)
    var destination = canonical(destination)
    try safe(source, destination)
    // Fail for missing/unreadable sources even if a conflict would otherwise be skipped.
    _ = try signature(source)
    if exists(destination) {
      let mergeable = try isDirectory(source) && isDirectory(destination)
      let resolution: ConflictResolution
      if let all = context.all {
        resolution = ConflictResolution(decision: all)
      } else {
        resolution = await resolve(
          FileConflict(
            source: source, destination: destination, isDirectoryMerge: mergeable))
      }
      // The resolver suspends the actor: recheck paths before any destructive action.
      try safe(source, destination)
      if resolution.applyToAll && resolution.decision != .merge {
        context.all = resolution.decision
      }
      switch resolution.decision {
      case .skip: return nil
      case .stop:
        context.stopped = true
        return nil
      case .keepBoth: destination = unique(destination)
      case .merge:
        guard mergeable, try isDirectory(source), try isDirectory(destination) else {
          throw LocalFileOperationError.invalidMerge
        }
        // A merge decision never implies replacement of colliding descendants.
        let inherited = context.all
        context.all = nil
        defer { context.all = inherited }
        let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
          .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for child in children {
          if context.stopped { break }
          _ = try await transferOne(
            source: child, destination: destination.appendingPathComponent(child.lastPathComponent),
            move: move, context: &context, resolve: resolve)
        }
        if move, try fm.contentsOfDirectory(atPath: source.path).isEmpty {
          try recordMove(source, storageURL(), in: &context.transaction)
        }
        return destination
      case .replaceOlder:
        let sourceDate = try fm.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
        let targetDate =
          try fm.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date
        guard let sourceDate, let targetDate, sourceDate > targetDate else { return nil }
        try recordMove(destination, storageURL(), in: &context.transaction)
      case .replace:
        try recordMove(destination, storageURL(), in: &context.transaction)
      }
    }
    if move {
      try recordMove(source, destination, in: &context.transaction)
    } else {
      try copy(source, to: destination, in: &context.transaction)
    }
    return destination
  }

  private func copy(_ source: URL, to destination: URL, in transaction: inout Transaction) throws {
    try absent(destination)
    let staged = try storageURL()
    try fm.copyItem(at: source, to: staged)
    // Copies are undone by moving them into storage, never by deleting user-visible contents.
    try recordMove(staged, destination, in: &transaction)
  }

  private func recordMove(_ source: URL, _ destination: URL, in transaction: inout Transaction)
    throws
  {
    let fingerprint = try signature(source)
    try absent(destination)
    do {
      try renameItem(source, destination)
    } catch {
      guard isCrossDevice(error) else { throw error }
      try fm.copyItem(at: source, to: destination)
      // Record the completed copy first so a failed source removal remains undoable.
      let stash = try storageURL()
      transaction.steps.append(Step(from: stash, to: destination, signature: fingerprint))
      transaction.cursor += 1
      guard try signature(source) == fingerprint,
        try signature(destination) == fingerprint
      else {
        throw LocalFileOperationError.changedContents
      }
      try removeItem(source)
      transaction.steps.removeLast()
      transaction.cursor -= 1
    }
    transaction.steps.append(Step(from: source, to: destination, signature: fingerprint))
    transaction.cursor += 1
  }

  private func guardedMove(_ source: URL, _ destination: URL, signature: Signature) throws {
    try check(source, destination, signature: signature)
    do { try renameItem(source, destination) } catch {
      guard isCrossDevice(error) else { throw error }
      try fm.copyItem(at: source, to: destination)
      guard try self.signature(source) == signature,
        try self.signature(destination) == signature
      else {
        throw LocalFileOperationError.changedContents
      }
      do {
        try removeItem(source)
      } catch {
        // A failed removal can partially delete a directory. Only unblock retry if
        // BOTH copies still match. Preserve the redundant copy in retained storage
        // rather than deleting it. If checks/relocation fail, leave both paths intact.
        if (try? self.signature(source)) == signature,
          (try? self.signature(destination)) == signature
        {
          try? Self.exclusiveRename(destination, storageURL(onVolumeOf: destination))
        }
        throw error
      }
    }
  }

  private func check(_ source: URL, _ destination: URL, signature expected: Signature) throws {
    try absent(destination)
    guard try signature(source) == expected else { throw LocalFileOperationError.changedContents }
  }

  private func signature(_ url: URL) throws -> Signature {
    let attributes = try fm.attributesOfItem(atPath: url.path)
    let type = attributes[.type] as? FileAttributeType
    if type == .typeSymbolicLink {
      return .link(try fm.destinationOfSymbolicLink(atPath: url.path))
    }
    if type == .typeDirectory {
      var children: [String: Signature] = [:]
      for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
        children[child.lastPathComponent] = try signature(child)
      }
      return .directory(children)
    }
    guard type == .typeRegular else { throw CocoaError(.fileReadUnsupportedScheme) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return .file(
      Data(hasher.finalize()), attributes[.modificationDate] as? Date,
      (attributes[.posixPermissions] as? NSNumber)?.uintValue)
  }

  private func local(_ url: URL) throws {
    guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
      throw LocalFileOperationError.nonLocalURL
    }
  }

  private func validate(_ name: String) throws {
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
      name.utf8.count <= 255
    else { throw LocalFileOperationError.invalidName }
  }

  // Resolve the parent, not the leaf: a symlink itself is copied/moved rather than its target.
  private func canonical(_ url: URL) -> URL {
    url.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(url.lastPathComponent).standardizedFileURL
  }

  private func safe(_ source: URL, _ destination: URL) throws {
    let source = canonical(source)
    let destination = canonical(destination)
    guard source.path != destination.path,
      !source.path.hasPrefix(destination.path + "/")
    else {
      throw LocalFileOperationError.unsafeTransfer
    }
    if try isDirectory(source) {
      let realSource = source.resolvingSymlinksInPath().path
      let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath().path
      guard parent != realSource, !parent.hasPrefix(realSource + "/") else {
        throw LocalFileOperationError.unsafeTransfer
      }
    }
  }

  private func isDirectory(_ url: URL) throws -> Bool {
    try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory
  }

  private func exists(_ url: URL) -> Bool {
    // Unlike fileExists, attributes also finds dangling symbolic links.
    (try? fm.attributesOfItem(atPath: url.path)) != nil
  }

  private func absent(_ url: URL) throws {
    guard !exists(url) else { throw LocalFileOperationError.destinationExists }
  }

  private func unique(_ url: URL) -> URL {
    let ext = url.pathExtension
    let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    var index = 1
    while true {
      let suffix = index == 1 ? " copy" : " copy \(index)"
      let name = stem + suffix + (ext.isEmpty ? "" : "." + ext)
      let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
      if !exists(candidate) { return candidate }
      index += 1
    }
  }

  private func storageURL() throws -> URL {
    let directory = fm.temporaryDirectory.appendingPathComponent(
      "FileTerm-operations-\(UUID().uuidString)")
    try fm.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    return directory.appendingPathComponent("item")
  }

  /// A syscall, not FileManager.moveItem: never silently copies or replaces a leaf.
  nonisolated static func exclusiveRename(_ source: URL, _ destination: URL) throws {
    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
      destination.withUnsafeFileSystemRepresentation { destinationPath in
        Darwin.renamex_np(sourcePath!, destinationPath!, UInt32(RENAME_EXCL))
      }
    }
    guard result == 0 else {
      let code = errno
      throw NSError(
        domain: NSPOSIXErrorDomain, code: Int(code),
        userInfo: [
          NSFilePathErrorKey: source.path,
          NSLocalizedDescriptionKey: String(cString: strerror(code)),
        ])
    }
  }

  // Failed history copy cleanup must stay on the destination volume so that its
  // relocation is a single exclusive rename, never another copy/delete fallback.
  private func storageURL(onVolumeOf url: URL) throws -> URL {
    let directory = url.deletingLastPathComponent()
      .appendingPathComponent(".FileTerm-recovery-\(UUID().uuidString)")
    try fm.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    return directory.appendingPathComponent("item")
  }

  private func isCrossDevice(_ error: any Error) -> Bool {
    let error = error as NSError
    if error.domain == NSPOSIXErrorDomain && error.code == 18 { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isCrossDevice(underlying)
    }
    return false
  }
}
