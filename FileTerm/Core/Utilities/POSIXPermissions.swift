import Foundation

/// Value-only permission editor. Special bits survive checkbox edits; file type bits are masked out.
public struct POSIXPermissions: Equatable, Sendable {
  public enum Subject: UInt16, CaseIterable, Sendable {
    case owner = 6
    case group = 3
    case other = 0
  }
  public enum Permission: UInt16, CaseIterable, Sendable {
    case read = 4
    case write = 2
    case execute = 1
  }

  public private(set) var mode: UInt16

  public init(mode: UInt16) { self.mode = mode & 0o7777 }

  public init(octal: String) throws {
    guard (3...4).contains(octal.count), octal.utf8.allSatisfy({ (48...55).contains($0) }),
      let mode = UInt16(octal, radix: 8)
    else { throw FileUtilityError.invalidPermissions }
    self.init(mode: mode)
  }

  /// Four digits, including the setuid/setgid/sticky digit.
  public var octal: String { String(format: "%04o", Int(mode)) }

  /// Nine characters without a file-type prefix; includes s/S and t/T for special bits.
  public var symbolic: String {
    Subject.allCases.map { subject in
      var result = contains(.read, for: subject) ? "r" : "-"
      result += contains(.write, for: subject) ? "w" : "-"
      let executable = contains(.execute, for: subject)
      let special: UInt16
      switch subject {
      case .owner: special = 0o4000
      case .group: special = 0o2000
      case .other: special = 0o1000
      }
      if mode & special != 0 {
        result += subject == .other ? (executable ? "t" : "T") : (executable ? "s" : "S")
      } else {
        result += executable ? "x" : "-"
      }
      return result
    }.joined()
  }

  public func contains(_ permission: Permission, for subject: Subject) -> Bool {
    mode & (permission.rawValue << subject.rawValue) != 0
  }

  public mutating func set(_ permission: Permission, for subject: Subject, enabled: Bool) {
    let mask = permission.rawValue << subject.rawValue
    mode = enabled ? mode | mask : mode & ~mask
  }
}
