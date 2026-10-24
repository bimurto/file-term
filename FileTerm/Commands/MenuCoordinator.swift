import AppKit
import FileTermCore

@MainActor final class MenuCoordinator: NSObject, NSMenuDelegate {
  private let registry: CommandRegistry

  init(registry: CommandRegistry) { self.registry = registry }

  func install() {
    let bar = NSMenu()
    for title in ["FileTerm", "File", "Edit", "View", "Go", "Commands", "Window"] {
      let menu = NSMenu(title: title)
      menu.autoenablesItems = false
      menu.delegate = self
      for command in registry.commands where command.menuPath.first == title {
        let item = NSMenuItem(
          title: command.title, action: #selector(execute(_:)),
          keyEquivalent: command.shortcut ?? "")
        item.target = self
        item.representedObject = command.id
        item.identifier = NSUserInterfaceItemIdentifier(command.id)
        item.keyEquivalentModifierMask = command.shortcutModifiers.reduce(
          into: NSEvent.ModifierFlags()
        ) {
          switch $1 {
          case .command: $0.insert(.command)
          case .shift: $0.insert(.shift)
          case .option: $0.insert(.option)
          case .control: $0.insert(.control)
          }
        }
        menu.addItem(item)
      }
      let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      root.submenu = menu
      bar.addItem(root)
      if title == "Window" { NSApp.windowsMenu = menu }
      menuNeedsUpdate(menu)
    }
    NSApp.mainMenu = bar
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    for item in menu.items {
      guard let id = item.representedObject as? String else { continue }
      let reason = registry.disabledReason(for: id)
      item.isEnabled = reason == nil
      item.toolTip = reason
      item.setAccessibilityHelp(reason)
    }
  }

  @objc private func execute(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    registry.execute(id)
  }
}
