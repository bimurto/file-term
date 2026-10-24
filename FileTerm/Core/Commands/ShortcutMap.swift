import Foundation

public struct Shortcut: Hashable, Codable, Sendable {
  public var key: String
  public var command: Bool
  public var shift: Bool
  public var option: Bool
  public var control: Bool

  public init(
    key: String, command: Bool = false, shift: Bool = false, option: Bool = false,
    control: Bool = false
  ) {
    self.key = key.lowercased()
    self.command = command
    self.shift = shift
    self.option = option
    self.control = control
  }

  public init(key: String, modifiers: Set<AppCommand.ShortcutModifier>) {
    self.init(
      key: key, command: modifiers.contains(.command), shift: modifiers.contains(.shift),
      option: modifiers.contains(.option), control: modifiers.contains(.control))
  }

  public var modifiers: Set<AppCommand.ShortcutModifier> {
    var result: Set<AppCommand.ShortcutModifier> = []
    if command { result.insert(.command) }
    if shift { result.insert(.shift) }
    if option { result.insert(.option) }
    if control { result.insert(.control) }
    return result
  }

  public static let escape = "\u{1B}"

  public var display: String {
    let name: String
    switch key {
    case Self.escape: name = "⎋"
    case "\r": name = "↩"
    case " ": name = "Space"
    case "\t": name = "⇥"
    case "\u{7F}": name = "⌫"
    default: name = key.uppercased()
    }
    return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
      + name
  }
}

/// A user override of a command's default shortcut. `shortcut == nil` means "no shortcut".
public struct ShortcutOverride: Hashable, Codable, Sendable {
  public var shortcut: Shortcut?
  public init(shortcut: Shortcut?) { self.shortcut = shortcut }
}

public struct ShortcutMap: Equatable, Sendable {
  public private(set) var defaults: [String: Shortcut]
  public private(set) var overrides: [String: ShortcutOverride]

  public init(defaults: [String: Shortcut], overrides: [String: ShortcutOverride] = [:]) {
    self.defaults = defaults
    self.overrides = overrides.filter { defaults[$0.key] != $0.value.shortcut }
  }

  public func effective(for id: String) -> Shortcut? {
    if let override = overrides[id] { return override.shortcut }
    return defaults[id]
  }

  public func isCustomized(_ id: String) -> Bool { overrides[id] != nil }

  /// Other commands that currently use `shortcut`.
  public func conflicts(for shortcut: Shortcut, excluding id: String, among ids: [String])
    -> [String]
  {
    ids.filter { $0 != id && effective(for: $0) == shortcut }
  }

  public mutating func assign(_ shortcut: Shortcut?, to id: String) {
    if defaults[id] == shortcut {
      overrides.removeValue(forKey: id)
    } else {
      overrides[id] = ShortcutOverride(shortcut: shortcut)
    }
  }

  public mutating func restoreDefault(_ id: String) { overrides.removeValue(forKey: id) }
  public mutating func restoreDefaults() { overrides = [:] }
}

/// Shortcuts the 4.6 defaults seed (see docs/milestones/M03).
public enum DefaultShortcuts {
  public static let quickSelect = Shortcut(key: "s", command: true)
  public static let quickOpen = Shortcut(key: Shortcut.escape)
  public static let newFolder = Shortcut(key: "n", command: true, shift: true)
  public static let newFolderWithSelection = Shortcut(key: "n", command: true, control: true)
  public static let newFile = Shortcut(key: "n", command: true, shift: true, option: true)
  public static let open = Shortcut(key: "o", command: true)
  public static let quickLook = Shortcut(key: "y", command: true)
}
