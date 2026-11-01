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
      for source in sources { total = Self.adding(total, try await size(of: source)) }
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
        let name = newName ?? entry.name
        guard FileName.isSafe(name) else {
          outcomes.skipped += 1
          log("Skipped \(source.path): unsafe name \(name)")
          continue
        }
        try await copyItem(entry, to: Self.child(folder, name))
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if committed > 0 { throw PartialTransferError(error.localizedDescription) }
      throw error
    }
    return outcomes
  }

  /// Copies, then deletes the sources. The sources are deleted only when every item was copied:
  /// a skipped or failed item, or a Stop, leaves all of them in place.
  public func move(sources: [Location], to folder: Location, newName: String? = nil)
    async throws -> TransferSummary
  {
    if sources.contains(where: {
      let path = Self.normalized($0.path)
      return $0.providerID == folder.providerID
        && Self.parentPath(path) == Self.normalized(folder.path)
        && (newName == nil || newName == (path as NSString).lastPathComponent)
    }) {
      throw FileSystemError.io("The items are already in this folder.")
    }
    let summary = try await copy(sources: sources, to: folder, newName: newName)
    guard summary.failed == 0, summary.skipped == 0, !stopped else {
      log("Sources kept: not every item was moved")
      return summary
    }
    for source in sources {
      try await control.checkpoint()
      do { try await provider(source.providerID).delete(source) } catch {
        throw PartialTransferError(
          "Copied, but could not delete \(source.path): \(error.localizedDescription)")
      }
    }
    return summary
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
    if source.providerID == destination.providerID {
      let from = Self.normalized(source.path)
      let to = Self.normalized(destination.path)
      // Replace would otherwise set aside and delete the only copy.
      if from == to { throw FileSystemError.io("An item cannot be copied onto itself.") }
      if entry.kind == .directory, to.hasPrefix(from + "/") {
        throw FileSystemError.io("A folder cannot be copied into itself.")
      }
    }
    let target = try provider(destination.providerID)
    var finalDestination = destination
    var replacing: FileEntry?
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
      case .replace: replacing = existing
      case .replaceOlder:
        guard let new = entry.modifiedAt, let old = existing.modifiedAt, new > old else {
          outcomes.skipped += 1
          return
        }
        replacing = existing
      default:
        outcomes.skipped += 1
        return
      }
    }
    if entry.kind == .directory {
      try await copyDirectory(
        entry, to: finalDestination, merging: merging, replacing: replacing != nil)
    } else {
      try await copyFile(entry, to: finalDestination, replacing: replacing)
    }
  }

  private func copyDirectory(
    _ entry: FileEntry, to destination: Location, merging: Bool, replacing: Bool
  ) async throws {
    let source = try provider(entry.location.providerID)
    let target = try provider(destination.providerID)
    let setAside = replacing ? try await self.setAside(destination, in: target) : nil
    do {
      if !merging {
        do { try await target.createDirectory(destination) } catch {
          outcomes.failed += 1
          throw error
        }
        committed += 1
      }
      for child in try await source.list(entry.location, includeHidden: true) {
        if stopped { break }
        guard FileName.isSafe(child.name) else {
          outcomes.skipped += 1
          log("Skipped an item with an unsafe name in \(entry.location.path): \(child.name)")
          continue
        }
        try await copyItem(child, to: Self.child(destination, child.name))
      }
    } catch {
      if let setAside { try await restore(setAside, to: destination, in: target, after: error) }
      throw error
    }
    if stopped {
      if let setAside { try await restore(setAside, to: destination, in: target, after: nil) }
      return
    }
    if let setAside { await discard(setAside, in: target) }
    outcomes.succeeded += 1
  }

  private func copyFile(_ entry: FileEntry, to destination: Location, replacing: FileEntry?)
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
      if let permissions = replacing?.permissions {
        do { try await target.setPermissions(permissions, of: temporary) } catch {
          if error as? FileSystemError != .unsupportedOperation {
            log("Could not keep the permissions of \(destination.path): \(error)")
          }
        }
      }
      let setAside = replacing == nil ? nil : try await self.setAside(destination, in: target)
      do { try await target.move(temporary, to: destination) } catch {
        if let setAside { try await restore(setAside, to: destination, in: target, after: error) }
        throw error
      }
      if let setAside { await discard(setAside, in: target) }
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

  // MARK: Replacing

  /// The old item stays on the server under a hidden name until the new one is in place.
  private func setAside(_ location: Location, in target: any FileSystemProvider) async throws
    -> Location
  {
    let path = Self.normalized(location.path)
    let aside = Self.child(
      Location(providerID: location.providerID, path: Self.parentPath(path)),
      ".\((path as NSString).lastPathComponent).fileterm-\(UUID().uuidString).old")
    try await target.move(location, to: aside)
    return aside
  }

  /// Puts the old item back, removing whatever partial new one is in its place. It must still run
  /// when the job itself was cancelled. If it can't, the error says where the old item is.
  private func restore(
    _ aside: Location, to destination: Location, in target: any FileSystemProvider,
    after failure: (any Error)?
  ) async throws {
    let restored = await Task.detached { () -> Bool in
      try? await target.delete(destination)
      do {
        try await target.move(aside, to: destination)
        return true
      } catch { return false }
    }.value
    guard restored else {
      let reason = failure.map { $0.localizedDescription + " " } ?? ""
      throw FileSystemError.io("\(reason)The old version is still at \(aside.path).")
    }
  }

  private func discard(_ aside: Location, in target: any FileSystemProvider) async {
    let removed = await Task.detached { () -> Bool in
      do {
        try await target.delete(aside)
        return true
      } catch { return false }
    }.value
    if !removed { log("Could not remove the old version at \(aside.path)") }
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
      let size = child.kind == .directory ? try await size(of: child.location) : child.size ?? 0
      total = Self.adding(total, size)
    }
    return total
  }

  private func provider(_ id: String) throws -> any FileSystemProvider {
    guard let provider = registry.provider(for: id) else {
      throw FileSystemError.unsupportedOperation
    }
    return provider
  }

  /// Connection paths can end in a slash, so paths are compared in this form.
  static func normalized(_ path: String) -> String {
    "/" + path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
  }

  static func parentPath(_ path: String) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
  }

  /// Sizes come from the server, so a sum stops at the maximum instead of trapping.
  private static func adding(_ first: Int64, _ second: Int64) -> Int64 {
    let (sum, overflow) = first.addingReportingOverflow(second)
    return overflow ? .max : sum
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
