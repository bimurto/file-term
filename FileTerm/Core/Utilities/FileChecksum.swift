import CryptoKit
import Darwin
import Foundation

public enum ChecksumAlgorithm: String, CaseIterable, Sendable {
  case md5, sha1, sha256
}

public struct ChecksumProgress: Equatable, Sendable {
  public let bytesRead: UInt64
  /// File size observed when opening. Concurrent external edits may change the final byte count.
  public let totalBytes: UInt64
}

public enum FileChecksum {
  /// Streams bounded chunks on the cooperative executor, not the main actor. Cancel the calling Task
  /// to stop between reads. Progress is ordered and awaited (including an initial zero-byte update).
  /// MD5/SHA-1 are compatibility checksums, not secure authentication primitives.
  public static func calculate(
    at url: URL, algorithm: ChecksumAlgorithm, chunkSize: Int = 1_048_576,
    progress: @Sendable (ChecksumProgress) async -> Void = { _ in }
  ) async throws -> String {
    try Task.checkCancellation()
    guard url.isFileURL else { throw FileUtilityError.nonLocalURL }
    guard chunkSize > 0 else { throw FileUtilityError.invalidChunkSize }
    // O_NOFOLLOW and O_NONBLOCK avoid following symlinks or blocking on a FIFO.
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard info.st_mode & S_IFMT == S_IFREG else { throw FileUtilityError.notRegularFile }
    let total = UInt64(max(0, info.st_size))
    switch algorithm {
    case .md5:
      return try await stream(
        Insecure.MD5(), handle: handle, total: total, chunkSize: chunkSize, progress: progress)
    case .sha1:
      return try await stream(
        Insecure.SHA1(), handle: handle, total: total, chunkSize: chunkSize, progress: progress)
    case .sha256:
      return try await stream(
        SHA256(), handle: handle, total: total, chunkSize: chunkSize, progress: progress)
    }
  }

  private static func stream<H: HashFunction>(
    _ initial: H, handle: FileHandle, total: UInt64, chunkSize: Int,
    progress: @Sendable (ChecksumProgress) async -> Void
  ) async throws -> String {
    var hash = initial
    var count: UInt64 = 0
    await progress(ChecksumProgress(bytesRead: 0, totalBytes: total))
    while true {
      try Task.checkCancellation()
      guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }
      hash.update(data: data)
      count += UInt64(data.count)
      await progress(ChecksumProgress(bytesRead: count, totalBytes: total))
      await Task.yield()
    }
    try Task.checkCancellation()
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
