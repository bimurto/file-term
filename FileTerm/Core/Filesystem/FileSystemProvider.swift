import Foundation

public struct Location: Hashable, Sendable {
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
  public let size: Int64?
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let typeIdentifier: String?

  public init(
    location: Location, name: String, kind: Kind, size: Int64? = nil,
    createdAt: Date? = nil, modifiedAt: Date? = nil, typeIdentifier: String? = nil
  ) {
    self.location = location
    self.name = name
    self.kind = kind
    self.size = size
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.typeIdentifier = typeIdentifier
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
  func stat(_ location: Location) async throws -> FileEntry
  func read(_ location: Location) async throws -> any FileByteReader
  /// Writes a new file. An existing destination is never overwritten.
  func write(_ contents: any FileByteReader, to location: Location) async throws
  func move(_ source: Location, to destination: Location) async throws
  /// Removes the item permanently. User-facing callers must confirm first.
  func delete(_ location: Location) async throws
}
