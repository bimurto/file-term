import AppKit
import FileTermCore

@MainActor final class MenuCoordinator: NSObject, NSMenuDelegate {
  private let registry: CommandRegistry
  private var paths: [ObjectIdentifier: [String]] = [:]
  private let servicesMenu = NSMenu(title: NSLocalizedString("Services", comment: "Menu title"))

  init(registry: CommandRegistry) { self.registry = registry }

  func install() {
    let bar = NSMenu()
    for title in ["FileTerm", "File", "Edit", "View", "Go", "Commands", "Window"] {
      let menu = makeMenu(path: [title])
      let root = NSMenuItem(
        title: NSLocalizedString(title, comment: "Menu title"), action: nil, keyEquivalent: "")
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

  func menuHasKeyEquivalent(
    _ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
    action: UnsafeMutablePointer<Selector?>
  ) -> Bool {
    updateEnabling(in: menu, states: registry.states())
    return false
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let path = paths[ObjectIdentifier(menu)] else { return }
    if path == ["Window"] || path == ["Edit"] {
      // AppKit owns OS-specific tiling controls and the live window list in Window, and Dictation,
      // Emoji & Symbols and AutoFill in Edit. Rebuilding these menus would remove them.
      removeRepeatedSystemItems(in: menu)
      let states = registry.states()
      for item in menu.items {
        guard let id = item.representedObject as? String, let state = states[id] else { continue }
        apply(state, to: item)
      }
      return
    }
    for item in menu.items { if let child = item.submenu { forget(child) } }
    menu.removeAllItems()
    populate(menu, path: path)
  }

  func menuWillOpen(_ menu: NSMenu) {
    if paths[ObjectIdentifier(menu)] == ["Edit"] { removeRepeatedSystemItems(in: menu) }
  }

  /// AppKit can add its Edit items again each time it updates a menu built in code.
  private func removeRepeatedSystemItems(in menu: NSMenu) {
    var seen: Set<String> = []
    for item in menu.items where item.representedObject == nil && !item.isSeparatorItem {
      if !seen.insert(item.title).inserted { menu.removeItem(item) }
    }
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
          let item = NSMenuItem(
            title: NSLocalizedString(title, comment: "Menu title"), action: nil, keyEquivalent: "")
          item.submenu = makeMenu(path: path + [title])
          menu.addItem(item)
        }
        continue
      }
      let shortcut = registry.effectiveShortcut(for: command.id)
      let item = NSMenuItem(
        title: NSLocalizedString(command.title, comment: "Menu command"),
        action: #selector(execute(_:)), keyEquivalent: shortcut?.key ?? "")
      item.target = self
      item.representedObject = command.id
      item.identifier = NSUserInterfaceItemIdentifier(command.id)
      item.keyEquivalentModifierMask = (shortcut?.modifiers ?? []).reduce(
        into: NSEvent.ModifierFlags()
      ) {
        switch $1 {
        case .command: $0.insert(.command)
        case .shift: $0.insert(.shift)
        case .option: $0.insert(.option)
        case .control: $0.insert(.control)
        }
      }
      apply(registry.state(of: command), to: item)
      menu.addItem(item)
    }
    if path == ["FileTerm"] { insertServices(in: menu) }
  }

  /// AppKit fills the Services menu with what is installed on this Mac, but only for the first menu
  /// it is given. A menu can have one parent, so this one moves to the rebuilt item.
  private func insertServices(in menu: NSMenu) {
    servicesMenu.supermenu?.items.first { $0.submenu === servicesMenu }?.submenu = nil
    let item = NSMenuItem(title: servicesMenu.title, action: nil, keyEquivalent: "")
    item.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    let hide = menu.indexOfItem(withRepresentedObject: "app.hide")
    menu.insertItem(item, at: hide >= 0 ? hide : menu.numberOfItems)
  }

  func refreshEnabling() {
    let states = registry.states()
    for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
      updateEnabling(in: menu, states: states)
    }
  }

  private func updateEnabling(in menu: NSMenu, states: [String: CommandRegistry.CommandState]) {
    for item in menu.items {
      if let child = item.submenu { updateEnabling(in: child, states: states) }
      guard let id = item.representedObject as? String, let state = states[id] else { continue }
      apply(state, to: item)
    }
  }

  private func apply(_ state: CommandRegistry.CommandState, to item: NSMenuItem) {
    item.isEnabled = state.disabledReason == nil
    item.toolTip = state.disabledReason
    item.setAccessibilityHelp(state.disabledReason)
    item.state = state.isChecked ? .on : .off
  }

  @objc private func execute(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    registry.execute(id)
  }
}
