import Foundation

/// One step of a batch rename. Rules run in list order, each on the part of the name it applies to.
public struct RenameRule: Codable, Hashable, Identifiable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case replaceText, changeCase, addSequence, addText, addDate

    public var title: String {
      switch self {
      case .replaceText: "Replace Text"
      case .changeCase: "Change Case"
      case .addSequence: "Add Sequence"
      case .addText: "Add Text"
      case .addDate: "Add Date"
      }
    }
  }

  public enum Target: String, Codable, CaseIterable, Sendable {
    case name, fileExtension, fullName
  }

  public enum Occurrence: String, Codable, CaseIterable, Sendable { case first, last, all }
  public enum CaseStyle: String, Codable, CaseIterable, Sendable {
    case lower, upper, title, sentence
  }
  public enum Position: String, Codable, CaseIterable, Sendable { case start, end, index }
  public enum DateSource: String, Codable, CaseIterable, Sendable { case modified, created, now }

  public var id = UUID()
  public var kind: Kind
  public var applyTo: Target = .name
  // Replace Text
  public var find = ""
  public var replacement = ""
  public var occurrence: Occurrence = .all
  public var caseSensitive = false
  // Change Case
  public var caseStyle: CaseStyle = .lower
  // Add Sequence
  public var start = 1
  public var step = 1
  public var padding = 1
  public var prefix = ""
  public var suffix = ""
  // Add Sequence, Add Text and Add Date
  public var position: Position = .start
  public var positionIndex = 0
  // Add Text
  public var text = ""
  // Add Date
  public var dateSource: DateSource = .modified
  public var dateFormat = "yyyy-MM-dd"

  public init(kind: Kind) { self.kind = kind }
}

/// What a rule needs to know about the item it renames.
public struct RenameItem: Identifiable, Hashable, Sendable {
  public var id: Location { location }
  public let location: Location
  public let name: String
  public let isDirectory: Bool
  public let modifiedAt: Date?
  public let createdAt: Date?

  public init(
    location: Location, name: String, isDirectory: Bool = false, modifiedAt: Date? = nil,
    createdAt: Date? = nil
  ) {
    self.location = location
    self.name = name
    self.isDirectory = isDirectory
    self.modifiedAt = modifiedAt
    self.createdAt = createdAt
  }
}

extension RenameRule {
  /// Applies this rule to a whole file name. Folders have no extension.
  func apply(to name: String, item: RenameItem, index: Int, now: Date) -> String {
    let parts = Self.split(name, isDirectory: item.isDirectory)
    switch applyTo {
    case .name:
      return Self.join(transform(parts.base, item: item, index: index, now: now), parts.ext)
    case .fileExtension:
      guard !item.isDirectory else { return name }
      return Self.join(parts.base, transform(parts.ext, item: item, index: index, now: now))
    case .fullName:
      return transform(name, item: item, index: index, now: now)
    }
  }

  static func split(_ name: String, isDirectory: Bool) -> (base: String, ext: String) {
    guard !isDirectory else { return (name, "") }
    let ext = (name as NSString).pathExtension
    guard !ext.isEmpty else { return (name, "") }
    return ((name as NSString).deletingPathExtension, ext)
  }

  static func join(_ base: String, _ ext: String) -> String {
    ext.isEmpty ? base : base + "." + ext
  }

  private func transform(_ value: String, item: RenameItem, index: Int, now: Date) -> String {
    switch kind {
    case .replaceText: return replacing(in: value)
    case .changeCase: return changingCase(of: value)
    case .addSequence:
      return inserting(
        prefix + Self.padded(start + step * index, to: padding) + suffix, into: value)
    case .addText: return inserting(text, into: value)
    case .addDate:
      let date: Date?
      switch dateSource {
      case .modified: date = item.modifiedAt
      case .created: date = item.createdAt
      case .now: date = now
      }
      guard let date else { return value }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = dateFormat
      return inserting(formatter.string(from: date), into: value)
    }
  }

  private func replacing(in value: String) -> String {
    guard !find.isEmpty else { return value }
    var options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
    switch occurrence {
    case .all:
      return value.replacingOccurrences(of: find, with: replacement, options: options)
    case .first, .last:
      if occurrence == .last { options.insert(.backwards) }
      guard let range = value.range(of: find, options: options) else { return value }
      return value.replacingCharacters(in: range, with: replacement)
    }
  }

  private func changingCase(of value: String) -> String {
    switch caseStyle {
    case .lower: return value.lowercased()
    case .upper: return value.uppercased()
    case .title: return value.capitalized
    case .sentence: return value.prefix(1).uppercased() + value.dropFirst().lowercased()
    }
  }

  private func inserting(_ piece: String, into value: String) -> String {
    switch position {
    case .start: return piece + value
    case .end: return value + piece
    case .index:
      let offset = min(max(positionIndex, 0), value.count)
      let at = value.index(value.startIndex, offsetBy: offset)
      return String(value[..<at]) + piece + String(value[at...])
    }
  }

  private static func padded(_ number: Int, to width: Int) -> String {
    let digits = String(number.magnitude)
    let zeros = String(repeating: "0", count: max(0, width - digits.count))
    return (number < 0 ? "-" : "") + zeros + digits
  }
}
