import Foundation

public struct CommandContext: Sendable {
  public let hasBrowserWindow: Bool
  public let hasKeyWindow: Bool
  public let isLoading: Bool
  public let sourceLocation: Location?
  public let targetLocation: Location?
  public let canGoBack: Bool
  public let canGoForward: Bool
  public let canGoUp: Bool
  public let canCoordinatePanes: Bool
  public let canEject: Bool
  public let tabCount: Int
  public let selectionCount: Int
  public let canQuickOpen: Bool
  public let isSearching: Bool

  public init(
    hasBrowserWindow: Bool, hasKeyWindow: Bool, isLoading: Bool,
    sourceLocation: Location? = nil, targetLocation: Location? = nil,
    canGoBack: Bool = false, canGoForward: Bool = false, canGoUp: Bool = false,
    canCoordinatePanes: Bool = false, canEject: Bool = false, tabCount: Int = 1,
    selectionCount: Int = 0, canQuickOpen: Bool = true, isSearching: Bool = false
  ) {
    self.hasBrowserWindow = hasBrowserWindow
    self.hasKeyWindow = hasKeyWindow
    self.isLoading = isLoading
    self.sourceLocation = sourceLocation
    self.targetLocation = targetLocation
    self.canGoBack = canGoBack
    self.canGoForward = canGoForward
    self.canGoUp = canGoUp
    self.canCoordinatePanes = canCoordinatePanes
    self.canEject = canEject
    self.tabCount = tabCount
    self.selectionCount = selectionCount
    self.canQuickOpen = canQuickOpen
    self.isSearching = isSearching
  }
}

@MainActor public struct AppCommand: Identifiable {
  public let id: String
  public let title: String
  public let menuPath: [String]
  public let shortcut: String?
  public let shortcutModifiers: Set<ShortcutModifier>
  public let isEnabled: (CommandContext) -> Bool
  public let disabledReason: (CommandContext) -> String
  public let isChecked: (CommandContext) -> Bool
  public let handler: () -> Void

  public enum ShortcutModifier: Hashable { case command, shift, option, control }

  public init(
    id: String, title: String, menuPath: [String], shortcut: String? = nil,
    shortcutModifiers: Set<ShortcutModifier> = [.command],
    isEnabled: @escaping (CommandContext) -> Bool,
    disabledReason: @escaping (CommandContext) -> String,
    isChecked: @escaping (CommandContext) -> Bool = { _ in false },
    handler: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.menuPath = menuPath
    self.shortcut = shortcut
    self.shortcutModifiers = shortcutModifiers
    self.isEnabled = isEnabled
    self.disabledReason = disabledReason
    self.isChecked = isChecked
    self.handler = handler
  }
}

@MainActor public final class CommandRegistry {
  private let baseCommands: [AppCommand]
  private let dynamicCommands: () -> [AppCommand]
  public var commands: [AppCommand] { baseCommands + dynamicCommands() }
  private let context: () -> CommandContext
  public private(set) var shortcutMap: ShortcutMap
  public var onShortcutOverridesChanged: (([String: ShortcutOverride]) -> Void)?

  public init(
    commands: [AppCommand], dynamicCommands: @escaping () -> [AppCommand] = { [] },
    shortcutOverrides: [String: ShortcutOverride] = [:],
    context: @escaping () -> CommandContext
  ) {
    precondition(Set(commands.map(\.id)).count == commands.count, "Command IDs must be unique")
    self.baseCommands = commands
    self.dynamicCommands = dynamicCommands
    self.context = context
    var defaults: [String: Shortcut] = [:]
    for command in commands {
      if let key = command.shortcut {
        defaults[command.id] = Shortcut(key: key, modifiers: command.shortcutModifiers)
      }
    }
    shortcutMap = ShortcutMap(defaults: defaults, overrides: shortcutOverrides)
  }

  public func effectiveShortcut(for id: String) -> Shortcut? { shortcutMap.effective(for: id) }

  public func shortcutConflicts(for shortcut: Shortcut, excluding id: String) -> [AppCommand] {
    let ids = shortcutMap.conflicts(
      for: shortcut, excluding: id, among: baseCommands.map(\.id))
    return ids.compactMap { command($0) }
  }

  public func assignShortcut(_ shortcut: Shortcut?, to id: String) {
    shortcutMap.assign(shortcut, to: id)
    onShortcutOverridesChanged?(shortcutMap.overrides)
  }

  public func restoreDefaultShortcuts() {
    shortcutMap.restoreDefaults()
    onShortcutOverridesChanged?(shortcutMap.overrides)
  }

  public func command(_ id: String) -> AppCommand? { commands.first { $0.id == id } }

  public func isChecked(_ id: String) -> Bool { command(id)?.isChecked(context()) ?? false }

  public func disabledReason(for id: String) -> String? {
    guard let command = command(id) else { return "Unknown command." }
    let current = context()
    return command.isEnabled(current) ? nil : command.disabledReason(current)
  }

  @discardableResult public func execute(_ id: String) -> Bool {
    guard let command = command(id), command.isEnabled(context()) else { return false }
    command.handler()
    return true
  }
}
