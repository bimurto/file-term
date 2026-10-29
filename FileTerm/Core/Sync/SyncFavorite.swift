import Foundation

/// A saved sync setup: both roots and every option. Running one always re-analyses first.
public struct SyncFavorite: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var left: Location
  public var right: Location
  public var options: SyncOptions

  public init(
    id: UUID = UUID(), name: String, left: Location, right: Location, options: SyncOptions
  ) {
    self.id = id
    self.name = name
    self.left = left
    self.right = right
    self.options = options
  }
}
