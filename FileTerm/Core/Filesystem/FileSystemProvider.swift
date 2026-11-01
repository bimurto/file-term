import Foundation
import os

public struct Location: Hashable, Codable, Sendable {
  public let providerID: String
  public let path: String

  public init(providerID: String, path: String) {
    self.providerID = providerID
    self.path = path
  }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
  public enum Kind: String, Sendable {
    case directory, file, symbolicLink, other
  }

  public var id: Location { location }
  public let location: Location
  public let name: String
  public let kind: Kind
  public var size: Int64?
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let typeIdentifier: String?
  public let addedAt: Date?
  public let openedAt: Date?
  public let tags: [String]
  public let owner: String?
  public let group: String?
  public let permissions: Int?
  public let isHidden: Bool

  public init(
    location: Location, name: String, kind: Kind, size: Int64? = nil,
    createdAt: Date? = nil, modifiedAt: Date? = nil, typeIdentifier: String? = nil,
    addedAt: Date? = nil, openedAt: Date? = nil, tags: [String] = [],
    owner: String? = nil, group: String? = nil, permissions: Int? = nil, isHidden: Bool = false
  ) {
    self.location = location
    self.name = name
    self.kind = kind
    self.size = size
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.typeIdentifier = typeIdentifier
    self.addedAt = addedAt
    self.openedAt = openedAt
    self.tags = tags
    self.owner = owner
    self.group = group
    self.permissions = permissions
    self.isHidden = isHidden
  }
}

/// Names that come from a server or an archive, which must stay one component of a local path.
public enum FileName {
  private static let logger = Logger(subsystem: "FileTerm", category: "RemoteNames")

  public static func isSafe(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
  }

  /// Whether a listing keeps this name. `.` and `..` are routine in listings, so only other
  /// rejected names are logged.
  static func isListable(_ name: String) -> Bool {
    if isSafe(name) { return true }
    if name != "." && name != ".." {
      logger.warning("Ignored an unsafe name in a listing: \(name, privacy: .public)")
    }
    return false
  }
}

public enum FileSystemError: Error, Equatable, Sendable, LocalizedError {
  case notFound, permissionDenied, destinationExists, unsupportedOperation
  case io(String)

  public var errorDescription: String? {
    switch self {
    case .notFound: "The item no longer exists."
    case .permissionDenied:
      "macOS denied access to this folder. Check the app’s Files and Folders permissions in System Settings."
    case .destinationExists: "An item already exists at the destination."
    case .unsupportedOperation: "This location does not support the operation."
    case .io(let message): message
    }
  }
}

/// A pull-based stream: providers read the next chunk only when requested.
public protocol FileByteReader: Sendable {
  func next() async throws -> Data?
}

public protocol FileSystemProvider: Sendable {
  var id: String { get }
  func list(_ location: Location) async throws -> [FileEntry]
  /// Lists a folder, optionally including hidden items. Defaults to the visible-only listing.
  func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry]
  /// A provider-supplied public/Base URL, distinct from a local file URL.
  func publicURL(for location: Location) async throws -> URL?
  func stat(_ location: Location) async throws -> FileEntry
  func read(_ location: Location) async throws -> any FileByteReader
  /// Writes a new file. An existing destination is never overwritten.
  func write(_ contents: any FileByteReader, to location: Location) async throws
  func move(_ source: Location, to destination: Location) async throws
  /// Creates one folder whose parent exists. An existing item is never reused.
  func createDirectory(_ location: Location) async throws
  /// Removes the item permanently. User-facing callers must confirm first.
  func delete(_ location: Location) async throws
}

extension FileSystemProvider {
  public func createDirectory(_ location: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }

  public func publicURL(for location: Location) async throws -> URL? { nil }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    try await list(location)
  }
}

/// A provider whose file names are raw bytes, read in a text encoding the user can change.
public protocol TextEncodingSwitchable: FileSystemProvider {
  func setTextEncoding(_ name: String) async
}

extension FTPProvider: TextEncodingSwitchable {}
extension SFTPProvider: TextEncodingSwitchable {}

/// A remote provider that can confirm the server speaks its protocol before it is registered.
public protocol ValidatingProvider: FileSystemProvider {
  func validate(root: String) async throws
  /// The absolute folder a connection opens first, from the Path the user typed.
  func resolveRoot(_ requested: String) async throws -> String
}

extension ValidatingProvider {
  public func resolveRoot(_ requested: String) async throws -> String {
    let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
  }
}
