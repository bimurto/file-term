import Foundation

public enum FileUtilityError: Error, LocalizedError, Equatable, Sendable {
  case nonLocalURL, invalidPermissions, invalidChunkSize, notRegularFile, sizeOverflow

  public var errorDescription: String? {
    switch self {
    case .nonLocalURL: return "This utility requires a local file URL."
    case .invalidPermissions: return "Enter three or four octal digits (0–7)."
    case .invalidChunkSize: return "The checksum chunk size must be greater than zero."
    case .notRegularFile: return "Checksums require a regular file, not a folder or symbolic link."
    case .sizeOverflow: return "The total logical file size is too large to represent."
    }
  }
}
