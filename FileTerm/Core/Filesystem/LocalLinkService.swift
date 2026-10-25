import Darwin
import Foundation

public enum LocalLinkKind: Sendable {
  case alias, symlink
}

public struct LocalLinkCapability: Sendable, Equatable {
  public let disabledReason: String?
  public var isSupported: Bool { disabledReason == nil }
}

public enum LocalLinkError: Error, LocalizedError, Sendable {
  case unavailable(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason): return reason
    }
  }
}

// Internal volume-query seam: unsupported volumes can be tested without mounting disks.
struct LinkVolumeCapabilities: Sendable {
  let symbolicLinks: Bool?
  let persistentIDs: Bool?
  let exclusiveRenaming: Bool?
  let readOnly: Bool?
}

/// Local links with unique names and no replacement of existing destination leaves.
/// Source parents are resolved, but source leaves are not: symlinks (even dangling
/// ones) link to the selected leaf, not its target. Finder aliases reject symlink
/// leaves because bookmark creation may silently resolve them instead.
public actor LocalLinkService {
  private let fm = FileManager.default
  private let volumeCapabilities: @Sendable (URL) throws -> LinkVolumeCapabilities

  public init() {
    volumeCapabilities = Self.readVolumeCapabilities
  }

  init(volumeCapabilities: @escaping @Sendable (URL) throws -> LinkVolumeCapabilities) {
    self.volumeCapabilities = volumeCapabilities
  }

  /// A best-effort UI preflight. Creation rechecks this and still propagates OS errors.
  /// A nil destination means the source's folder; otherwise it must be a directory.
  public func capability(
    for kind: LocalLinkKind, source: URL, in destinationDirectory: URL? = nil
  ) -> LocalLinkCapability {
    do {
      _ = try prepare(kind: kind, source: source, directory: destinationDirectory)
      return LocalLinkCapability(disabledReason: nil)
    } catch {
      return LocalLinkCapability(disabledReason: error.localizedDescription)
    }
  }

  public func createSymlink(source: URL, in destinationDirectory: URL? = nil) throws -> URL {
    let (source, parent) = try prepare(
      kind: .symlink, source: source, directory: destinationDirectory)
    return try publishUnique(source: source, parent: parent, kind: .symlink) { destination in
      // symlink(2) exclusively creates the leaf, including when a dangling link exists.
      let result = source.withUnsafeFileSystemRepresentation { sourcePath in
        destination.withUnsafeFileSystemRepresentation { destinationPath in
          Darwin.symlink(sourcePath!, destinationPath!)
        }
      }
      if result != 0 { throw Self.posixError(errno, path: destination.path) }
    }
  }

  public func createAlias(source: URL, in destinationDirectory: URL? = nil) throws -> URL {
    let (source, parent) = try prepare(
      kind: .alias, source: source, directory: destinationDirectory)
    let bookmark = try source.bookmarkData(
      options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
    // writeBookmarkData overwrites its output. Write only inside a private directory,
    // then publish with RENAME_EXCL on the destination volume, never at a user path.
    let staging = parent.appendingPathComponent(".FileTerm-alias-\(UUID().uuidString)")
    try fm.createDirectory(
      at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: staging) }
    let staged = staging.appendingPathComponent("alias")
    try URL.writeBookmarkData(bookmark, to: staged)
    return try publishUnique(source: source, parent: parent, kind: .alias) { destination in
      let result = staged.withUnsafeFileSystemRepresentation { sourcePath in
        destination.withUnsafeFileSystemRepresentation { destinationPath in
          Darwin.renamex_np(sourcePath!, destinationPath!, UInt32(RENAME_EXCL))
        }
      }
      if result != 0 { throw Self.posixError(errno, path: destination.path) }
    }
  }

  private func prepare(kind: LocalLinkKind, source: URL, directory: URL?) throws -> (URL, URL) {
    try requireLocal(source)
    if let directory { try requireLocal(directory) }
    let source = source.deletingLastPathComponent().resolvingSymlinksInPath()
      .appendingPathComponent(source.lastPathComponent)
    let parent = (directory ?? source.deletingLastPathComponent()).resolvingSymlinksInPath()
    let attributes = try fm.attributesOfItem(atPath: source.path)
    let type = attributes[.type] as? FileAttributeType
    guard type == .typeRegular || type == .typeDirectory || type == .typeSymbolicLink else {
      throw LocalLinkError.unavailable("Only files, folders and symbolic links can be linked.")
    }
    if kind == .alias && type == .typeSymbolicLink {
      throw LocalLinkError.unavailable(
        "Finder aliases to symbolic links are not supported. Use Make Symlink instead.")
    }
    guard
      try fm.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType == .typeDirectory
    else {
      throw LocalLinkError.unavailable("The link destination must be a folder.")
    }
    let destinationVolume = try volumeCapabilities(parent)
    guard destinationVolume.readOnly == false else {
      throw LocalLinkError.unavailable(
        "The destination volume is read-only or its write support is unknown.")
    }
    guard fm.isWritableFile(atPath: parent.path) else {
      throw LocalLinkError.unavailable("The destination folder is not writable.")
    }
    switch kind {
    case .symlink:
      guard destinationVolume.symbolicLinks == true else {
        throw LocalLinkError.unavailable(
          "The destination filesystem does not report symbolic-link support.")
      }
    case .alias:
      // There is no volumeSupportsAliases key. Persistent IDs support Finder's
      // bookmark tracking; exclusive rename is required for safe publication.
      let sourceVolume = try volumeCapabilities(source.deletingLastPathComponent())
      guard sourceVolume.persistentIDs == true, destinationVolume.persistentIDs == true,
        destinationVolume.exclusiveRenaming == true
      else {
        throw LocalLinkError.unavailable(
          "Finder aliases require persistent file IDs and a destination supporting exclusive rename."
        )
      }
    }
    return (source, parent)
  }

  private func requireLocal(_ url: URL) throws {
    guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
      !url.path.contains("\0")
    else {
      throw LocalLinkError.unavailable("Links require local file URLs without null characters.")
    }
  }

  private func publishUnique(
    source: URL, parent: URL, kind: LocalLinkKind, write: (URL) throws -> Void
  ) throws -> URL {
    var index = 1
    while true {
      let suffix = (kind == .alias ? " alias" : " symlink") + (index == 1 ? "" : " \(index)")
      var stem = source.lastPathComponent
      // Truncate at Character boundaries, leaving room for the collision suffix.
      while stem.utf8.count + suffix.utf8.count > 255 { stem.removeLast() }
      let destination = parent.appendingPathComponent(stem + suffix)
      do {
        try write(destination)
        return destination
      } catch {
        let error = error as NSError
        guard error.domain == NSPOSIXErrorDomain, error.code == Int(EEXIST) else { throw error }
        index += 1
      }
    }
  }

  private static func readVolumeCapabilities(_ url: URL) throws -> LinkVolumeCapabilities {
    let values = try url.resourceValues(forKeys: [
      .volumeSupportsSymbolicLinksKey, .volumeSupportsPersistentIDsKey,
      .volumeSupportsExclusiveRenamingKey, .volumeIsReadOnlyKey,
    ])
    return LinkVolumeCapabilities(
      symbolicLinks: values.volumeSupportsSymbolicLinks,
      persistentIDs: values.volumeSupportsPersistentIDs,
      exclusiveRenaming: values.volumeSupportsExclusiveRenaming, readOnly: values.volumeIsReadOnly)
  }

  private static func posixError(_ code: Int32, path: String) -> NSError {
    NSError(
      domain: NSPOSIXErrorDomain, code: Int(code),
      userInfo: [
        NSFilePathErrorKey: path, NSLocalizedDescriptionKey: String(cString: strerror(code)),
      ])
  }
}
