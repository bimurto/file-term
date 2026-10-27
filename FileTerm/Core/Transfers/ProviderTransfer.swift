import CryptoKit
import Foundation

public struct LocationConflict: Sendable {
  public let source: Location
  public let destination: Location
  public let isDirectoryMerge: Bool
  public init(source: Location, destination: Location, isDirectoryMerge: Bool) {
    self.source = source
    self.destination = destination
    self.isDirectoryMerge = isDirectoryMerge
  }
}

public typealias LocationConflictResolver = @Sendable (LocationConflict) async -> ConflictResolution

/// Copies between any two providers by streaming through the app, one chunk at a time.
/// Every chunk goes through `TransferControl.advance`, which provides progress, throttling,
/// pause and cancellation. Files are written under a hidden temporary name and moved into place
/// only when complete, so a partial file is never visible under its real name.
public actor ProviderTransfer {
  private let registry: ProviderRegistry
  private let control: TransferControl
  private let verification: CopyVerification
  private let resolve: LocationConflictResolver
  private let log: @Sendable (String) -> Void
  private var outcomes = TransferSummary()
  private var committed = 0
  private var stopped = false
  private var sticky: [Bool: ConflictDecision] = [:]

  public init(
    registry: ProviderRegistry, control: TransferControl, verification: CopyVerification = .none,
    log: @escaping @Sendable (String) -> Void = { _ in },
    resolve: @escaping LocationConflictResolver = { _ in ConflictResolution(decision: .skip) }
  ) {
    self.registry = registry
    self.control = control
    self.verification = verification
    self.log = log
    self.resolve = resolve
  }

  public func outcomeSummary() -> TransferSummary { outcomes }

  /// Best-effort total size for progress; nil when any part cannot be listed.
  public func totalBytes(of sources: [Location]) async -> Int64? {
    do {
      var total: Int64 = 0
      for source in sources { total += try await size(of: source) }
      return total
    } catch { return nil }
  }

  public func copy(sources: [Location], to folder: Location, newName: String? = nil)
    async throws -> TransferSummary
  {
    do {
      for source in sources {
        if stopped { break }
        let entry = try await provider(source.providerID).stat(source)
        try await copyItem(entry, to: Self.child(folder, newName ?? entry.name))
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if committed > 0 { throw PartialTransferError(error.localizedDescription) }
      throw error
    }
    return outcomes
  }

  // MARK: Items

  private func copyItem(_ entry: FileEntry, to destination: Location) async throws {
    try await control.checkpoint()
    let source = entry.location
    guard entry.kind == .file || entry.kind == .directory else {
      outcomes.skipped += 1
      log("Skipped \(source.path): links and special files are not copied between locations")
      return
    }
    if source.providerID == destination.providerID, entry.kind == .directory,
      destination.path == source.path || destination.path.hasPrefix(source.path + "/")
    {
      throw FileSystemError.io("A folder cannot be copied into itself.")
    }
    let target = try provider(destination.providerID)
    var finalDestination = destination
    var replacing: Location?
    var merging = false
    if let existing = try await existingItem(destination, in: target) {
      let isMerge = entry.kind == .directory && existing.kind == .directory
      let decision = await decide(
        LocationConflict(source: source, destination: destination, isDirectoryMerge: isMerge))
      log("Conflict: \(decision) — \(destination.path)")
      switch decision {
      case .skip:
        outcomes.skipped += 1
        return
      case .stop:
        stopped = true
        return
      case .keepBoth: finalDestination = try await uniqueName(destination, in: target)
      case .merge where isMerge: merging = true
      case .replace: replacing = destination
      case .replaceOlder:
        guard let new = entry.modifiedAt, let old = existing.modifiedAt, new > old else {
          outcomes.skipped += 1
          return
        }
        replacing = destination
      default:
        outcomes.skipped += 1
        return
      }
    }
    if entry.kind == .directory {
      try await copyDirectory(entry, to: finalDestination, merging: merging, replacing: replacing)
    } else {
      try await copyFile(entry, to: finalDestination, replacing: replacing)
    }
  }

  private func copyDirectory(
    _ entry: FileEntry, to destination: Location, merging: Bool, replacing: Location?
  ) async throws {
    let source = try provider(entry.location.providerID)
    let target = try provider(destination.providerID)
    if let replacing { try await target.delete(replacing) }
    if !merging {
      do { try await target.createDirectory(destination) } catch {
        outcomes.failed += 1
        throw error
      }
      committed += 1
    }
    for child in try await source.list(entry.location, includeHidden: true) {
      if stopped { return }
      try await copyItem(child, to: Self.child(destination, child.name))
    }
    outcomes.succeeded += 1
  }

  private func copyFile(_ entry: FileEntry, to destination: Location, replacing: Location?)
    async throws
  {
    let source = try provider(entry.location.providerID)
    let target = try provider(destination.providerID)
    let name = (destination.path as NSString).lastPathComponent
    let temporary = Location(
      providerID: destination.providerID,
      path: Self.child(
        Location(providerID: destination.providerID, path: Self.parentPath(destination.path)),
        ".\(name).fileterm-\(UUID().uuidString).part"
      ).path)
    let reader = MeteredReader(
      base: try await source.read(entry.location), control: control,
      hashing: verification == .checksum)
    do {
      try await target.write(reader, to: temporary)
      try await verify(entry, copied: reader.bytes, sourceHash: reader.digest, at: temporary)
      if let replacing { try await target.delete(replacing) }
      try await target.move(temporary, to: destination)
    } catch {
      outcomes.failed += Task.isCancelled ? 0 : 1
      // Cleanup must still run when the job itself was cancelled.
      await Task.detached { try? await target.delete(temporary) }.value
      throw error
    }
    committed += 1
    outcomes.succeeded += 1
  }

  private func verify(_ entry: FileEntry, copied: Int64, sourceHash: Data?, at temporary: Location)
    async throws
  {
    if let expected = entry.size, expected != copied {
      throw FileSystemError.io("\(entry.name) changed while it was being copied.")
    }
    let source = try provider(entry.location.providerID)
    if let fresh = try? await source.stat(entry.location),
      fresh.size != entry.size || fresh.modifiedAt != entry.modifiedAt
    {
      throw FileSystemError.io("\(entry.name) changed while it was being copied.")
    }
    guard verification != .none else { return }
    let target = try provider(temporary.providerID)
    guard try await target.stat(temporary).size == copied else {
      throw FileSystemError.io("Verification failed: the copied size of \(entry.name) is wrong.")
    }
    guard verification == .checksum, let sourceHash else { return }
    let check = try await target.read(temporary)
    var hash = SHA256()
    while let chunk = try await check.next() {
      try await control.checkpoint()
      hash.update(data: chunk)
    }
    guard Data(hash.finalize()) == sourceHash else {
      throw FileSystemError.io("Verification failed: the checksum of \(entry.name) differs.")
    }
  }

  // MARK: Helpers

  private func decide(_ conflict: LocationConflict) async -> ConflictDecision {
    if let remembered = sticky[conflict.isDirectoryMerge] { return remembered }
    let answer = await resolve(conflict)
    if answer.applyToAll { sticky[conflict.isDirectoryMerge] = answer.decision }
    return answer.decision
  }

  private func existingItem(_ location: Location, in provider: any FileSystemProvider)
    async throws -> FileEntry?
  {
    do { return try await provider.stat(location) } catch FileSystemError.notFound { return nil }
  }

  private func uniqueName(_ location: Location, in provider: any FileSystemProvider)
    async throws -> Location
  {
    let name = (location.path as NSString).lastPathComponent
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    let folder = Location(providerID: location.providerID, path: Self.parentPath(location.path))
    for number in 2..<1000 {
      let candidate = Self.child(
        folder, ext.isEmpty ? "\(name) \(number)" : "\(stem) \(number).\(ext)")
      if try await existingItem(candidate, in: provider) == nil { return candidate }
    }
    throw FileSystemError.destinationExists
  }

  private func size(of location: Location) async throws -> Int64 {
    try Task.checkCancellation()
    let source = try provider(location.providerID)
    let entry = try await source.stat(location)
    guard entry.kind == .directory else { return entry.kind == .file ? entry.size ?? 0 : 0 }
    var total: Int64 = 0
    for child in try await source.list(location, includeHidden: true) {
      total += child.kind == .directory ? try await size(of: child.location) : child.size ?? 0
    }
    return total
  }

  private func provider(_ id: String) throws -> any FileSystemProvider {
    guard let provider = registry.provider(for: id) else {
      throw FileSystemError.unsupportedOperation
    }
    return provider
  }

  static func parentPath(_ path: String) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
  }

  static func child(_ folder: Location, _ name: String) -> Location {
    Location(
      providerID: folder.providerID,
      path: folder.path.hasSuffix("/") ? folder.path + name : folder.path + "/" + name)
  }
}

/// Single-consumer wrapper that reports every chunk to the transfer control.
private final class MeteredReader: FileByteReader, @unchecked Sendable {
  private let base: any FileByteReader
  private let control: TransferControl
  private var hash: SHA256?
  private(set) var bytes: Int64 = 0

  init(base: any FileByteReader, control: TransferControl, hashing: Bool) {
    self.base = base
    self.control = control
    hash = hashing ? SHA256() : nil
  }

  var digest: Data? { hash.map { Data($0.finalize()) } }

  func next() async throws -> Data? {
    guard let chunk = try await base.next() else { return nil }
    hash?.update(data: chunk)
    bytes += Int64(chunk.count)
    try await control.advance(bytes: Int64(chunk.count))
    return chunk
  }
}
