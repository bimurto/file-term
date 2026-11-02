import AppKit
import FileTermCore
import Observation

/// The browser window's native toolbar. `settings.workspace.toolbarItems` holds its items, and
/// changes made in the Customize Toolbar palette are saved back there.
@MainActor final class BrowserToolbar: NSObject, NSToolbarDelegate {
  let toolbar = NSToolbar(identifier: "BrowserToolbar")
  private let settings: AppSettings
  private let registry: CommandRegistry
  private let makeSearch: () -> NSView
  /// Toolbars with one identifier mirror each other's changes, so while any window rebuilds its
  /// items, no window saves them.
  private static var isApplying = false

  init(settings: AppSettings, registry: CommandRegistry, search: @escaping () -> NSView) {
    self.settings = settings
    self.registry = registry
    makeSearch = search
    super.init()
    toolbar.delegate = self
    toolbar.allowsUserCustomization = true
    toolbar.displayMode = .iconOnly
  }

  func attach(to window: NSWindow) {
    Self.isApplying = true
    window.toolbar = toolbar
    Self.isApplying = false
    observe()
  }

  /// Saves the items if the user changed them. Moving an item may not report an add or remove,
  /// so this also runs when the customization palette closes.
  func save() {
    guard !Self.isApplying else { return }
    let ids = toolbar.items.map(\.itemIdentifier.rawValue)
    if ids != shownItems { settings.workspace.toolbarItems = ids }
  }

  private func observe() {
    withObservationTracking {
      apply(shownItems)
      refresh()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observe() }
    }
  }

  private var toolItems: [String] {
    settings.tools.filter(\.showInToolbar).map { "tools.run.\($0.id)" }
  }

  /// The saved items this version knows, then any tool shown in the toolbar but not yet placed.
  private var shownItems: [String] {
    let commands = Set(registry.commands.map(\.id))
    let tools = toolItems
    let saved = ToolbarLayout.items(from: settings.workspace.toolbarItems).filter { id in
      if id.hasPrefix("tools.run.") { return tools.contains(id) }
      return commands.contains(id) || ToolbarLayout.Group(itemID: id) != nil
        || [ToolbarLayout.search, ToolbarLayout.space, ToolbarLayout.flexibleSpace].contains(id)
    }
    return saved + tools.filter { !saved.contains($0) }
  }

  private func apply(_ ids: [String]) {
    guard toolbar.items.map(\.itemIdentifier.rawValue) != ids else { return }
    Self.isApplying = true
    defer { Self.isApplying = false }
    while !toolbar.items.isEmpty { toolbar.removeItem(at: 0) }
    for (index, id) in ids.enumerated() {
      toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(id), at: index)
    }
  }

  /// Reads every command's state in one pass, as menus do.
  private func refresh() {
    let states = registry.states()
    for item in toolbar.items {
      let id = item.itemIdentifier.rawValue
      if let group = item as? NSToolbarItemGroup, let kind = ToolbarLayout.Group(itemID: id) {
        group.selectedIndex = kind.commands.firstIndex { states[$0]?.isChecked == true } ?? -1
        for (subitem, command) in zip(group.subitems, kind.commands) {
          subitem.isEnabled = states[command]?.disabledReason == nil
        }
      } else if let button = item.view as? NSButton, let state = states[id] {
        button.state = state.isChecked ? .on : .off
        button.setAccessibilityValue(state.isChecked ? "Shown" : "Hidden")
        button.isEnabled = state.disabledReason == nil
        button.image = image(for: id)
        button.toolTip = state.disabledReason ?? item.label
        item.menuFormRepresentation?.state = button.state
      }
    }
  }

  private func title(of id: String) -> String {
    registry.command(id).map { registry.title(of: $0) } ?? id
  }

  private func image(for id: String) -> NSImage? {
    let symbol =
      id.hasPrefix("tools.run.")
      ? "hammer"
      : id == "view.showHidden"
        ? (settings.showHidden ? "eye" : "eye.slash") : ToolbarSymbols.symbol(for: id)
    return NSImage(systemSymbolName: symbol, accessibilityDescription: title(of: id))
  }

  @objc private func run(_ sender: Any?) {
    let id =
      (sender as? NSMenuItem)?.representedObject as? String
      ?? toolbar.items.first { $0.view === sender as AnyObject }?.itemIdentifier.rawValue
    guard let id else { return }
    registry.execute(id)
    // A command that changed nothing leaves its toggle button flipped.
    refresh()
  }

  @objc private func select(_ sender: NSToolbarItemGroup) {
    guard let group = ToolbarLayout.Group(itemID: sender.itemIdentifier.rawValue),
      group.commands.indices.contains(sender.selectedIndex)
    else { return }
    registry.execute(group.commands[sender.selectedIndex])
    refresh()
  }

  /// What the Customize Toolbar palette offers besides the groups, search and tools: the
  /// commands worth a button, each with its own symbol in `ToolbarSymbols`.
  private static let paletteCommands = [
    "go.back", "go.forward", "go.enclosingFolder", "go.toFolder", "go.syncBrowsing",
    "view.clonePane", "view.swapPanes", "commands.edit", "commands.compare", "file.share",
    "commands.rename", "file.getInfo", "file.openInTerminal", "go.favorites.manage",
    "commands.compress", "view.refresh", "commands.sync", "view.showHidden", "view.preview",
    "file.quickLook", "go.connect", "view.activities", "view.logs", "view.terminal",
    "commands.copyTo", "commands.moveTo", "file.trash", "file.newFolder", "file.newFile",
  ]

  // MARK: NSToolbarDelegate

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    WorkspacePreferences().toolbarItems.map { NSToolbarItem.Identifier($0) }
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    let commands = Self.paletteCommands.filter { registry.command($0) != nil }
    let ids =
      ToolbarLayout.Group.allCases.map(\.itemID) + [ToolbarLayout.search] + commands + toolItems
      + [ToolbarLayout.space, ToolbarLayout.flexibleSpace]
    return ids.map { NSToolbarItem.Identifier($0) }
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    let id = identifier.rawValue
    if id == ToolbarLayout.search {
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.label = "Search"
      item.paletteLabel = "Search"
      item.view = makeSearch()
      item.visibilityPriority = .high
      return item
    }
    if let group = ToolbarLayout.Group(itemID: id) {
      let item = NSToolbarItemGroup(
        itemIdentifier: identifier, images: group.commands.compactMap(image(for:)),
        selectionMode: .selectOne, labels: group.commands.map(title(of:)), target: self,
        action: #selector(select(_:)))
      item.controlRepresentation = .expanded
      item.label = group.title
      item.paletteLabel = group.title
      item.toolTip = group.title
      return item
    }
    guard registry.command(id) != nil else { return nil }
    let title = title(of: id)
    let button = ToolbarButton(
      image: image(for: id) ?? NSImage(), target: self, action: #selector(run(_:)))
    button.bezelStyle = .toolbar
    button.setButtonType(.pushOnPushOff)
    button.setAccessibilityIdentifier(id == "view.showHidden" ? "showHiddenToggle" : id)
    button.setAccessibilityLabel(title)
    let menuItem = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
    menuItem.target = self
    menuItem.representedObject = id
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = title
    item.paletteLabel = title
    item.view = button
    item.menuFormRepresentation = menuItem
    return item
  }

  func toolbarWillAddItem(_ notification: Notification) { saveSoon() }
  func toolbarDidRemoveItem(_ notification: Notification) { saveSoon() }

  /// Waits until the add or remove has finished, so `items` is complete.
  private func saveSoon() {
    guard !Self.isApplying else { return }
    Task { @MainActor [weak self] in
      self?.save()
      self?.refresh()
    }
  }
}

/// A toggle look for checked commands, announced as a button like any other toolbar command.
private final class ToolbarButton: NSButton {
  override func accessibilityRole() -> NSAccessibility.Role? { .button }
}
