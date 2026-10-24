import AppKit
import FileTermCore

@MainActor final class MenuCoordinator: NSObject, NSMenuDelegate {
  private let registry: CommandRegistry
  private var paths: [ObjectIdentifier: [String]] = [:]

  init(registry: CommandRegistry) { self.registry = registry }

  func install() {
    let bar = NSMenu()
    for title in ["FileTerm", "File", "Edit", "View", "Go", "Commands", "Window"] {
      let menu = makeMenu(path: [title])
      let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      root.submenu = menu
      bar.addItem(root)
      if title == "Window" { NSApp.windowsMenu = menu }
    }
    NSApp.mainMenu = bar
  }

  private func makeMenu(path: [String]) -> NSMenu {
    let menu = NSMenu(title: path.last ?? "")
    menu.autoenablesItems = false
    menu.delegate = self
    paths[ObjectIdentifier(menu)] = path
    populate(menu, path: path)
    return menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let path = paths[ObjectIdentifier(menu)] else { return }
    if path == ["Window"] {
      // AppKit owns OS-specific tiling controls and the live window list in this menu.
      for item in menu.items {
        guard let id = item.representedObject as? String, registry.command(id) != nil else {
          continue
        }
        let reason = registry.disabledReason(for: id)
        item.isEnabled = reason == nil
        item.toolTip = reason
        item.setAccessibilityHelp(reason)
        item.state = registry.isChecked(id) ? .on : .off
      }
      return
    }
    for item in menu.items { if let child = item.submenu { forget(child) } }
    menu.removeAllItems()
    populate(menu, path: path)
  }

  private func forget(_ menu: NSMenu) {
    paths.removeValue(forKey: ObjectIdentifier(menu))
    for item in menu.items { if let child = item.submenu { forget(child) } }
  }

  private func populate(_ menu: NSMenu, path: [String]) {
    var submenus: Set<String> = []
    for command in registry.commands where command.menuPath.starts(with: path) {
      if command.menuPath.count > path.count {
        let title = command.menuPath[path.count]
        if submenus.insert(title).inserted {
          let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
          item.submenu = makeMenu(path: path + [title])
          menu.addItem(item)
        }
        continue
      }
      let item = NSMenuItem(
        title: command.title, action: #selector(execute(_:)), keyEquivalent: command.shortcut ?? "")
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
      let reason = registry.disabledReason(for: command.id)
      item.isEnabled = reason == nil
      item.toolTip = reason
      item.setAccessibilityHelp(reason)
      item.state = registry.isChecked(command.id) ? .on : .off
      menu.addItem(item)
    }
  }

  @objc private func execute(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    registry.execute(id)
  }
}
