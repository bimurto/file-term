import Foundation

public struct CommandContext: Sendable {
  public let hasBrowserWindow: Bool
  public let hasKeyWindow: Bool
  public let isLoading: Bool

  public init(hasBrowserWindow: Bool, hasKeyWindow: Bool, isLoading: Bool) {
    self.hasBrowserWindow = hasBrowserWindow
    self.hasKeyWindow = hasKeyWindow
    self.isLoading = isLoading
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
  public let handler: () -> Void

  public enum ShortcutModifier: Hashable { case command, shift, option, control }

  public init(
    id: String, title: String, menuPath: [String], shortcut: String? = nil,
    shortcutModifiers: Set<ShortcutModifier> = [.command],
    isEnabled: @escaping (CommandContext) -> Bool,
    disabledReason: @escaping (CommandContext) -> String,
    handler: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.menuPath = menuPath
    self.shortcut = shortcut
    self.shortcutModifiers = shortcutModifiers
    self.isEnabled = isEnabled
    self.disabledReason = disabledReason
    self.handler = handler
  }
}

@MainActor public final class CommandRegistry {
  public let commands: [AppCommand]
  private let context: () -> CommandContext

  public init(commands: [AppCommand], context: @escaping () -> CommandContext) {
    precondition(Set(commands.map(\.id)).count == commands.count, "Command IDs must be unique")
    self.commands = commands
    self.context = context
  }

  public func command(_ id: String) -> AppCommand? { commands.first { $0.id == id } }

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
