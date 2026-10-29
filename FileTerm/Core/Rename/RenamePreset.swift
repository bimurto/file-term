import Foundation

/// A saved rule list that can be loaded into Batch Rename or started from Quick Open.
public struct RenamePreset: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var rules: [RenameRule]

  public init(id: UUID = UUID(), name: String, rules: [RenameRule]) {
    self.id = id
    self.name = name
    self.rules = rules
  }
}
