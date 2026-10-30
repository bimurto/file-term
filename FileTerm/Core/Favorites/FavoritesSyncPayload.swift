import Foundation

/// The favorites list as it would travel through iCloud: the list only, never file contents.
public struct FavoritesSyncPayload: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var favorites: [FavoriteNode]

  public init(favorites: [FavoriteNode], version: Int = FavoritesSyncPayload.currentVersion) {
    self.version = version
    self.favorites = favorites
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  /// Rejects data written by a newer version instead of dropping fields it does not know.
  public static func decode(_ data: Data) throws -> FavoritesSyncPayload {
    let payload = try JSONDecoder().decode(FavoritesSyncPayload.self, from: data)
    guard payload.version <= currentVersion else { throw FavoritesSyncError.newerVersion }
    return payload
  }
}

public enum FavoritesSyncError: Error, Equatable {
  case newerVersion
}
