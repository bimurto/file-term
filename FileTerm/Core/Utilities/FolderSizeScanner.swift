import Darwin
import Foundation

public struct FolderSizeProgress: Equatable, Sendable {
  public let logicalBytes: UInt64
  public let filesCounted: UInt64
  public let itemsVisited: UInt64
}

public enum FolderSizeScanner {
  /// Counts regular-file logical bytes (not allocated blocks), including hidden files and packages.
  /// Directories and symlinks contribute zero; hard links count once per directory entry.
  /// A regular-file root is also supported. Filesystem errors throw rather than return partial totals.
  /// The tree is not a snapshot: concurrent edits may affect results. Descriptor-relative traversal
  /// with O_NOFOLLOW prevents a directory replaced by a symlink from escaping the tree.
  /// Progress starts at zero, is awaited for each visited entry, and has no known total in advance.
  /// Cancel the calling Task to stop between entries; this work is not main-actor isolated.
  public static func scan(
    at url: URL, progress: @Sendable (FolderSizeProgress) async -> Void = { _ in }
  ) async throws -> FolderSizeProgress {
    try Task.checkCancellation()
    guard url.isFileURL else { throw FileUtilityError.nonLocalURL }
    var state = FolderSizeProgress(logicalBytes: 0, filesCounted: 0, itemsVisited: 0)
    await progress(state)
    try Task.checkCancellation()
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw posixError() }
    if info.st_mode & S_IFMT == S_IFDIR {
      let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
      guard fd >= 0 else { throw posixError() }
      try await walk(fd, state: &state, progress: progress)
    } else {
      state = try adding(info, to: state)
      await progress(state)
    }
    try Task.checkCancellation()
    return state
  }

  /// Takes ownership of the directory descriptor, including on failure/cancellation.
  private static func walk(
    _ fd: Int32, state: inout FolderSizeProgress,
    progress: @Sendable (FolderSizeProgress) async -> Void
  ) async throws {
    guard let directory = fdopendir(fd) else {
      let error = posixError()
      close(fd)
      throw error
    }
    defer { closedir(directory) }
    while true {
      try Task.checkCancellation()
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { throw posixError() }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      if name == "." || name == ".." { continue }
      var info = stat()
      guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
      state = try adding(info, to: state)
      await progress(state)
      try Task.checkCancellation()
      if info.st_mode & S_IFMT == S_IFDIR {
        let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard child >= 0 else { throw posixError() }
        try await walk(child, state: &state, progress: progress)
      }
      await Task.yield()
    }
  }

  private static func adding(_ info: stat, to state: FolderSizeProgress) throws
    -> FolderSizeProgress
  {
    let regular = info.st_mode & S_IFMT == S_IFREG
    let bytes = regular ? UInt64(max(0, info.st_size)) : 0
    let (total, overflow) = state.logicalBytes.addingReportingOverflow(bytes)
    guard !overflow else { throw FileUtilityError.sizeOverflow }
    return FolderSizeProgress(
      logicalBytes: total, filesCounted: state.filesCounted + (regular ? 1 : 0),
      itemsVisited: state.itemsVisited + 1)
  }

  private static func posixError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
