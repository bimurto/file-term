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
  private var transferControl: TransferControl?
  private var verification: CopyVerification = .none
  private var outcomes = TransferSummary()

  /// Counts transferred entries (merged folders count their immediate child outcomes).
  public func outcomeSummary() -> TransferSummary { outcomes }

  /// Retain transactions even when external changes currently prevent their undo.
  public func hasUndoHistory() -> Bool { !undoStack.isEmpty }

  public func setTransferControl(
    _ control: TransferControl?, verification: CopyVerification = .none
  ) {
    // Do not replace a running operation's cancellation/progress context.
    guard !busy else { return }
    transferControl = control
    self.verification = verification
  }

  private func checkpoint() async throws {
    try Task.checkCancellation()
    try await transferControl?.checkpoint()
  }
  private var undoStack: [Transaction] = []
  private var redoStack: [Transaction] = []

  private struct Step {
    var from: URL
    let to: URL
    let signature: Signature
    /// Undo sends a copy to the Trash, and `from` then records where it landed.
    var isCopy = false
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
  private let trashItem: @Sendable (URL) throws -> URL

  public init() {
    renameItem = { try Self.exclusiveRename($0, $1) }
    removeItem = { try FileManager.default.removeItem(at: $0) }
    trashItem = { try Self.moveToTrash($0) }
  }

  // Internal syscall seams allow deterministic EXDEV/deletion-failure tests without mounts.
  init(
    rename: @escaping @Sendable (URL, URL) throws -> Void,
    remove: @escaping @Sendable (URL) throws -> Void
  ) {
    renameItem = rename
    removeItem = remove
    trashItem = { try Self.moveToTrash($0) }
  }

  // Lets tests undo copies without filling the real Trash.
  init(trash: @escaping @Sendable (URL) throws -> URL) {
    renameItem = { try Self.exclusiveRename($0, $1) }
    removeItem = { try FileManager.default.removeItem(at: $0) }
    trashItem = trash
  }

  public func create(in parent: URL, name: String, directory: Bool) async throws -> URL {
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
    try await recordMove(staged, destination, in: &transaction)
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
    try await recordMove(staged, destination, in: &context.transaction)
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

  public func duplicate(sources: [URL]) async throws -> [URL] {
    try begin()
    defer { busy = false }
    var transaction = Transaction()
    defer { commit(transaction) }
    var results: [URL] = []
    for source in sources {
      try local(source)
      let destination = unique(canonical(source))
      do {
        try await copy(source, to: destination, in: &transaction)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        outcomes.failed += 1
        throw error
      }
      outcomes.succeeded += 1
      results.append(destination)
    }
    return results
  }

  public func rename(source: URL, name: String) async throws -> URL {
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
    try await recordMove(source, destination, in: &transaction)
    return destination
  }

  /// Renames several items as one undoable step. Swaps and case-only changes go through a
  /// temporary name so an item never lands on a name another one still holds.
  public func renameBatch(_ renames: [(source: URL, name: String)]) async throws -> [URL] {
    try begin()
    defer { busy = false }
    for rename in renames {
      try validate(rename.name)
      try local(rename.source)
    }
    let pairs = renames.map { (path: canonical($0.source).path, name: $0.name) }
    var transaction = Transaction()
    defer { commit(transaction) }
    for step in RenameSequencer.steps(for: pairs) {
      let from = URL(fileURLWithPath: step.path)
      try await recordMove(
        from, from.deletingLastPathComponent().appendingPathComponent(step.name), in: &transaction)
    }
    return pairs.map {
      URL(fileURLWithPath: $0.path).deletingLastPathComponent().appendingPathComponent($0.name)
    }
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
        let destination = try Self.moveToTrash(source)
        transaction.steps.append(Step(from: source, to: destination, signature: fingerprint))
        transaction.cursor += 1
        results.append(destination)
      }
      return results
    }
  #endif

  /// Removes items for good: no Trash, no undo step. Callers must confirm first.
  public func deletePermanently(sources: [URL]) throws {
    try begin()
    defer { busy = false }
    for source in sources {
      try Task.checkCancellation()
      try local(source)
      try fm.removeItem(at: canonical(source))
    }
  }

  public func undo() async throws {
    try begin()
    defer { busy = false }
    guard var transaction = undoStack.popLast() else { throw LocalFileOperationError.nothingToUndo }
    do {
      while transaction.cursor > 0 {
        let index = transaction.cursor - 1
        let step = transaction.steps[index]
        if step.isCopy {
          try await checkpoint()
          try check(step.to, step.from, signature: step.signature)
          transaction.steps[index].from = try trashItem(step.to)
        } else {
          try await guardedMove(step.to, step.from, signature: step.signature)
        }
        transaction.cursor -= 1
      }
      redoStack.append(transaction)
    } catch {
      undoStack.append(transaction)
      throw error
    }
  }

  public func redo() async throws {
    try begin()
    defer { busy = false }
    guard var transaction = redoStack.popLast() else { throw LocalFileOperationError.nothingToRedo }
    do {
      while transaction.cursor < transaction.steps.count {
        let step = transaction.steps[transaction.cursor]
        try await guardedMove(step.from, step.to, signature: step.signature)
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
    outcomes = TransferSummary()
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
    // Descendant failures are already counted by their recursive call.
    var handlingChildren = false
    var completed = false
    defer {
      if !completed && !handlingChildren && !Task.isCancelled { outcomes.failed += 1 }
    }
    do {
      return try await transferEntry(
        source: source, destination: destination, move: move, context: &context,
        resolve: resolve, handlingChildren: &handlingChildren, completed: &completed)
    } catch is CancellationError {
      completed = true
      throw CancellationError()
    }
  }

  private func transferEntry(
    source: URL, destination: URL, move: Bool, context: inout TransferContext,
    resolve: ConflictResolver, handlingChildren: inout Bool, completed: inout Bool
  ) async throws -> URL? {
    try await checkpoint()
    try local(source)
    try local(destination)
    let source = canonical(source)
    var destination = canonical(destination)
    try safe(source, destination)
    // Fail for missing/unreadable sources even if a conflict would otherwise be skipped.
    _ = try await cooperativeSignature(source)
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
      try await checkpoint()
      try safe(source, destination)
      if resolution.applyToAll && resolution.decision != .merge {
        context.all = resolution.decision
      }
      switch resolution.decision {
      case .skip:
        outcomes.skipped += 1
        completed = true
        return nil
      case .stop:
        if transferControl != nil { throw CancellationError() }
        // Preserve the legacy direct-operation contract; controlled queue jobs
        // instead surface Stop as cancellation while retaining partial history.
        context.stopped = true
        completed = true
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
        handlingChildren = true
        for child in children {
          if context.stopped { break }
          _ = try await transferOne(
            source: child, destination: destination.appendingPathComponent(child.lastPathComponent),
            move: move, context: &context, resolve: resolve)
        }
        if move, try fm.contentsOfDirectory(atPath: source.path).isEmpty {
          try await recordMove(source, storageURL(), in: &context.transaction)
        }
        if children.isEmpty { outcomes.succeeded += 1 }
        completed = true
        return destination
      case .replaceOlder:
        let sourceDate = try fm.attributesOfItem(atPath: source.path)[.modificationDate] as? Date
        let targetDate =
          try fm.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date
        guard let sourceDate, let targetDate, sourceDate > targetDate else {
          outcomes.skipped += 1
          completed = true
          return nil
        }
        try await recordMove(destination, storageURL(), in: &context.transaction)
      case .replace:
        try await recordMove(destination, storageURL(), in: &context.transaction)
      }
    }
    if move {
      try await recordMove(source, destination, in: &context.transaction)
    } else {
      try await copy(source, to: destination, in: &context.transaction)
    }
    outcomes.succeeded += 1
    completed = true
    return destination
  }

  private func copy(_ source: URL, to destination: URL, in transaction: inout Transaction)
    async throws
  {
    try absent(destination)
    let original = try await cooperativeSignature(source)
    let staged = try storageURL(onVolumeOf: destination)
    var published = false
    defer {
      if !published {
        try? fm.removeItem(at: staged)
        _ = staged.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
          Darwin.rmdir($0!)
        }
      }
    }
    try await copyTree(source, to: staged)
    guard try await cooperativeSignature(source) == original else {
      throw LocalFileOperationError.changedContents
    }
    if verification == .checksum {
      guard try await cooperativeSignature(staged) == original else {
        throw LocalFileOperationError.changedContents
      }
    }
    try await checkpoint()
    // Copies are undone by moving them to the Trash, never by deleting user-visible contents.
    try await recordMove(staged, destination, in: &transaction)
    transaction.steps[transaction.steps.count - 1].isCopy = true
    published = true
    _ = staged.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
      Darwin.rmdir($0!)
    }
  }

  /// Bounded reads, no symlink traversal, and no user-visible partial output.
  private func copyTree(_ source: URL, to destination: URL) async throws {
    try await checkpoint()
    let before = try fm.attributesOfItem(atPath: source.path)
    switch before[.type] as? FileAttributeType {
    case .typeSymbolicLink:
      try fm.createSymbolicLink(
        atPath: destination.path,
        withDestinationPath: fm.destinationOfSymbolicLink(atPath: source.path))
      return
    case .typeDirectory:
      try fm.createDirectory(at: destination, withIntermediateDirectories: false)
      let children = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
      for child in children {
        try await copyTree(child, to: destination.appendingPathComponent(child.lastPathComponent))
      }
      let after = try fm.contentsOfDirectory(atPath: source.path)
      guard Set(after) == Set(children.map(\.lastPathComponent)) else {
        throw LocalFileOperationError.changedContents
      }
    case .typeRegular:
      let descriptor = source.withUnsafeFileSystemRepresentation {
        Darwin.open($0!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      }
      guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? input.close() }
      var opened = stat()
      guard Darwin.fstat(descriptor, &opened) == 0,
        opened.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
        UInt64(opened.st_ino) == (before[.systemFileNumber] as? NSNumber)?.uint64Value
      else { throw LocalFileOperationError.changedContents }
      try Data().write(to: destination, options: .withoutOverwriting)
      let output = try FileHandle(forWritingTo: destination)
      defer { try? output.close() }
      var copied: Int64 = 0
      var hash = SHA256()
      while true {
        try await checkpoint()
        guard let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty else { break }
        try output.write(contentsOf: chunk)
        copied += Int64(chunk.count)
        if verification == .checksum { hash.update(data: chunk) }
        try await transferControl?.advance(bytes: Int64(chunk.count))
      }
      try output.synchronize()
      let after = try fm.attributesOfItem(atPath: source.path)
      guard (before[.size] as? NSNumber)?.int64Value == copied,
        (after[.size] as? NSNumber)?.int64Value == copied,
        before[.modificationDate] as? Date == after[.modificationDate] as? Date,
        before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber
      else { throw LocalFileOperationError.changedContents }
      if verification != .none {
        let size = try fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        guard size?.int64Value == copied else { throw LocalFileOperationError.changedContents }
      }
      if verification == .checksum {
        let check = try FileHandle(forReadingFrom: destination)
        defer { try? check.close() }
        var destinationHash = SHA256()
        while let chunk = try check.read(upToCount: 65_536), !chunk.isEmpty {
          try await checkpoint()
          destinationHash.update(data: chunk)
        }
        guard Data(hash.finalize()) == Data(destinationHash.finalize()) else {
          throw LocalFileOperationError.changedContents
        }
      }
    default: throw CocoaError(.fileReadUnsupportedScheme)
    }
    // copyfile's metadata-only mode preserves ACLs, extended attributes/resource forks,
    // dates and permissions without recopying data or following symbolic links.
    try await checkpoint()
    let status = source.withUnsafeFileSystemRepresentation { from in
      destination.withUnsafeFileSystemRepresentation { to in
        Darwin.copyfile(from, to, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW))
      }
    }
    guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }

  private func recordMove(_ source: URL, _ destination: URL, in transaction: inout Transaction)
    async throws
  {
    try await checkpoint()
    let fingerprint = try await cooperativeSignature(source)
    try absent(destination)
    do {
      try renameItem(source, destination)
    } catch {
      guard isCrossDevice(error) else { throw error }
      let staged = try storageURL(onVolumeOf: destination)
      defer {
        try? fm.removeItem(at: staged)
        _ = staged.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
          Darwin.rmdir($0!)
        }
      }
      try await copyTree(source, to: staged)
      guard try await cooperativeSignature(source) == fingerprint,
        try await cooperativeSignature(staged) == fingerprint
      else { throw LocalFileOperationError.changedContents }
      try await checkpoint()
      try Self.exclusiveRename(staged, destination)
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

  private func guardedMove(_ source: URL, _ destination: URL, signature: Signature) async throws {
    try await checkpoint()
    try check(source, destination, signature: signature)
    do { try renameItem(source, destination) } catch {
      guard isCrossDevice(error) else { throw error }
      let staged = try storageURL(onVolumeOf: destination)
      defer {
        try? fm.removeItem(at: staged)
        _ = staged.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
          Darwin.rmdir($0!)
        }
      }
      try await copyTree(source, to: staged)
      guard try await cooperativeSignature(source) == signature,
        try await cooperativeSignature(staged) == signature
      else { throw LocalFileOperationError.changedContents }
      try await checkpoint()
      try Self.exclusiveRename(staged, destination)
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

  private func cooperativeSignature(_ url: URL) async throws -> Signature {
    try await checkpoint()
    let attributes = try fm.attributesOfItem(atPath: url.path)
    let type = attributes[.type] as? FileAttributeType
    if type == .typeSymbolicLink {
      return .link(try fm.destinationOfSymbolicLink(atPath: url.path))
    }
    if type == .typeDirectory {
      var children: [String: Signature] = [:]
      for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
        children[child.lastPathComponent] = try await cooperativeSignature(child)
      }
      return .directory(children)
    }
    guard type == .typeRegular else { throw CocoaError(.fileReadUnsupportedScheme) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
      try await checkpoint()
      hasher.update(data: chunk)
    }
    return .file(
      Data(hasher.finalize()), attributes[.modificationDate] as? Date,
      (attributes[.posixPermissions] as? NSNumber)?.uintValue)
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
    guard FileName.isSafe(name), name.utf8.count <= 255
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

  nonisolated static func moveToTrash(_ url: URL) throws -> URL {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    guard let destination = resulting as URL? else { throw CocoaError(.fileWriteUnknown) }
    return destination
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
