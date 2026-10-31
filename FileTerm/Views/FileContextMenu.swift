import AppKit
import FileTermCore
import SwiftUI

/// Marks an icon or column row, so a right click can tell which item it landed on.
struct ContextMenuAnchor: NSViewRepresentable {
  let entry: FileEntry
  let pane: PaneModel
  let open: (FileEntry) -> Void

  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ view: AnchorView, context: Context) {
    view.entry = entry
    view.pane = pane
    view.open = open
  }

  @MainActor final class AnchorView: NSView {
    var entry: FileEntry?
    weak var pane: PaneModel?
    var open: ((FileEntry) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A view hosted by SwiftUI can report a visible area larger than itself, so both are checked.
    func isShowing(_ windowPoint: NSPoint) -> Bool {
      let point = convert(windowPoint, from: nil)
      return bounds.contains(point) && visibleRect.contains(point)
    }
  }
}

/// Handles right clicks on a pane's files before SwiftUI does. The selection has to change first,
/// because every menu item asks the command registry about the selection.
struct FileContextMenuHost: NSViewRepresentable {
  let pane: PaneModel
  let paneID: PaneID
  let browser: BrowserModel
  let registry: CommandRegistry
  let settings: AppSettings
  let cloudFiles: CloudFileActions?

  func makeNSView(context: Context) -> HostView { HostView() }
  func updateNSView(_ view: HostView, context: Context) { view.configuration = self }
  static func dismantleNSView(_ view: HostView, coordinator: ()) { view.stopMonitoring() }

  @MainActor final class HostView: NSView {
    var configuration: FileContextMenuHost?
    private var monitor: Any?
    private var menuContent: FileContextMenuBuilder?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
        let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
        return handled ? nil : event
      }
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    /// Returns true when this view takes the click, so nothing else opens a menu for it.
    private func handle(_ event: NSEvent) -> Bool {
      let point = convert(event.locationInWindow, from: nil)
      guard let configuration, let window, event.window === window, window.attachedSheet == nil,
        bounds.contains(point), visibleRect.contains(point),
        let contentView = window.contentView, let frame = contentView.superview
      else { return false }
      let hit = contentView.hitTest(frame.convert(event.locationInWindow, from: nil))
      if hit is NSText || hit?.enclosing(NSTableHeaderView.self) != nil { return false }

      configuration.browser.activePaneID = configuration.paneID
      let pane = configuration.pane
      if pane.viewOptions.mode == .list {
        guard let table = hit?.enclosing(NSTableView.self) else { return false }
        applySelectionRule(to: table, at: event.locationInWindow)
      } else if let anchor = anchor(at: event.locationInWindow, in: contentView, pane: pane),
        let entry = anchor.entry
      {
        // An earlier column's row isn't in this folder, so the commands can't act on it.
        guard pane.visibleEntries.contains(where: { $0.id == entry.id }) else {
          show(FileContextMenuBuilder.openOnly(entry, open: anchor.open), event: event)
          return true
        }
        if !pane.selection.contains(entry.id) { pane.selection = [entry.id] }
      } else {
        pane.selection = []
      }
      // The table reports its selection change to SwiftUI after this event.
      Task { @MainActor in
        show(FileContextMenuBuilder(configuration: configuration), event: event)
      }
      return true
    }

    private func applySelectionRule(to table: NSTableView, at location: NSPoint) {
      let row = table.row(at: table.convert(location, from: nil))
      let isHeader = row >= 0 && table.delegate?.tableView?(table, isGroupRow: row) == true
      if row < 0 || isHeader {
        table.deselectAll(nil)
      } else if !table.selectedRowIndexes.contains(row) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      }
    }

    private func anchor(
      at location: NSPoint, in view: NSView, pane: PaneModel
    ) -> ContextMenuAnchor.AnchorView? {
      if let anchor = view as? ContextMenuAnchor.AnchorView, anchor.pane === pane,
        anchor.isShowing(location)
      {
        return anchor
      }
      for child in view.subviews {
        if let found = self.anchor(at: location, in: child, pane: pane) { return found }
      }
      return nil
    }

    private func show(_ content: FileContextMenuBuilder, event: NSEvent) {
      menuContent = content
      NSMenu.popUpContextMenu(content.menu(), with: event, for: self)
      content.runPendingCommand()
    }
  }
}

extension NSView {
  fileprivate func enclosing<View: NSView>(_ type: View.Type) -> View? {
    var view: NSView? = self
    while let current = view {
      if let match = current as? View { return match }
      view = current.superview
    }
    return nil
  }
}

/// Builds one right-click menu. The menu's items hold it weakly, so its host keeps it alive.
@MainActor final class FileContextMenuBuilder: NSObject, NSMenuDelegate {
  private static let contentsLimit = 1000

  private let configuration: FileContextMenuHost?
  private var states: [String: CommandRegistry.CommandState] = [:]
  private var openOnlyEntry: FileEntry?
  private var openOnlyAction: ((FileEntry) -> Void)?
  private var pendingCommand: String?

  init(configuration: FileContextMenuHost) { self.configuration = configuration }

  private init(entry: FileEntry, open: ((FileEntry) -> Void)?) {
    configuration = nil
    openOnlyEntry = entry
    openOnlyAction = open
  }

  static func openOnly(_ entry: FileEntry, open: ((FileEntry) -> Void)?) -> FileContextMenuBuilder {
    FileContextMenuBuilder(entry: entry, open: open)
  }

  func menu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    guard let configuration else {
      let item = NSMenuItem(
        title: NSLocalizedString("Open", comment: "Menu command"),
        action: #selector(openOnly), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
      return menu
    }
    states = configuration.registry.states()
    let entries = configuration.pane.selectedEntries
    if entries.isEmpty {
      addFolderItems(to: menu)
    } else {
      addItems(for: entries, to: menu, configuration: configuration)
    }
    return menu
  }

  /// What a right click on empty space offers. These commands use the current folder when nothing
  /// is selected.
  private func addFolderItems(to menu: NSMenu) {
    menu.addItem(command("file.newFolder"))
    menu.addItem(command("file.newFile"))
    menu.addItem(.separator())
    menu.addItem(command("file.getInfo"))
    menu.addItem(command("file.quickLook"))
    menu.addItem(.separator())
    menu.addItem(submenu("Copy Path", path: ["File", "Copy Path"]))
    menu.addItem(.separator())
    menu.addItem(command("view.options"))
    addServices(to: menu)
  }

  private func addItems(
    for entries: [FileEntry], to menu: NSMenu, configuration: FileContextMenuHost
  ) {
    let single = entries.count == 1 ? entries.first : nil
    let isLocal = entries.allSatisfy { $0.location.providerID == "local" }
    let isPackage = single.map { Self.isPackage($0) } ?? false
    let folder = single.flatMap { $0.kind == .directory && !isPackage ? $0 : nil }
    let count = entries.count
    if single == nil {
      menu.addItem(command("file.newFolderWithSelection"))
      menu.addItem(.separator())
    }
    menu.addItem(command("file.open"))
    if folder != nil {
      menu.addItem(command("file.openInNewTab"))
    }
    menu.addItem(openWithItem(entries))
    if isPackage { menu.addItem(command("file.packageContents")) }
    if let folder, isLocal {
      menu.addItem(.separator())
      menu.addItem(contentsItem(folder))
    }
    menu.addItem(.separator())
    menu.addItem(
      isLocal
        ? command("file.trash")
        : command("commands.delete"))
    menu.addItem(.separator())
    menu.addItem(command("file.getInfo"))
    menu.addItem(
      command(
        "commands.rename",
        title: single == nil
          ? String(
            format: NSLocalizedString("Rename %d Items…", comment: "Context menu"), count)
          : nil))
    menu.addItem(
      command(
        "commands.compress",
        title: single.map {
          String(format: NSLocalizedString("Compress \"%@\"", comment: "Context menu"), $0.name)
        } ?? String(format: NSLocalizedString("Compress %d Items", comment: "Context menu"), count)
      ))
    menu.addItem(command("commands.duplicate"))
    menu.addItem(command("file.makeAlias"))
    menu.addItem(command("file.quickLook"))
    menu.addItem(command("file.revealInFinder"))
    menu.addItem(command("file.share"))
    if isLocal { addCloudItems(to: menu, single: single, cloudFiles: configuration.cloudFiles) }
    menu.addItem(.separator())
    menu.addItem(
      command(
        "edit.text.copy",
        title: single.map {
          String(format: NSLocalizedString("Copy \"%@\"", comment: "Context menu"), $0.name)
        } ?? String(format: NSLocalizedString("Copy %d Items", comment: "Context menu"), count)))
    menu.addItem(submenu("Copy Path", path: ["File", "Copy Path"]))
    menu.addItem(.separator())
    menu.addItem(command("view.options"))
    menu.addItem(.separator())
    menu.addItem(command("file.tags"))
    menu.addItem(tagDots(configuration.settings.tags))
    addServices(to: menu)
  }

  /// AppKit fills only the Services menu in the app menu, so this lists copies of its items.
  private func addServices(to menu: NSMenu) {
    guard let installed = NSApp.servicesMenu else { return }
    installed.update()
    let services = installed.items.filter { !$0.isSeparatorItem && $0.isEnabled }
    guard !services.isEmpty else { return }
    let parent = NSMenuItem(
      title: NSLocalizedString("Services", comment: "Menu title"), action: nil, keyEquivalent: "")
    parent.identifier = NSUserInterfaceItemIdentifier("context.Services")
    let submenu = NSMenu(title: parent.title)
    for service in services {
      if let copy = service.copy() as? NSMenuItem { submenu.addItem(copy) }
    }
    parent.submenu = submenu
    menu.addItem(.separator())
    menu.addItem(parent)
  }

  private func addCloudItems(
    to menu: NSMenu, single: FileEntry?, cloudFiles: CloudFileActions?
  ) {
    if states["file.iCloud.download"]?.disabledReason == nil {
      menu.addItem(command("file.iCloud.download"))
    }
    if states["file.iCloud.removeDownload"]?.disabledReason == nil {
      menu.addItem(
        command("file.iCloud.removeDownload", title: "Remove Download (Keeps File in iCloud)"))
    }
    if let single, let cloudFiles,
      case let state = cloudFiles.dropboxLinkState(single.location.path)
    {
      switch state {
      case .ready, .unavailable: menu.addItem(command("file.copyDropboxLink"))
      case .outsideDropbox: break
      }
    }
  }

  private static func isPackage(_ entry: FileEntry) -> Bool {
    guard entry.location.providerID == "local" else { return false }
    let url = URL(fileURLWithPath: entry.location.path)
    return url.pathExtension.lowercased() == "app"
      || NSWorkspace.shared.isFilePackage(atPath: url.path)
  }

  // MARK: Items

  private func command(_ id: String, title: String? = nil) -> NSMenuItem {
    let registered = configuration?.registry.command(id)
    let item = NSMenuItem(
      title: title.map { NSLocalizedString($0, comment: "Menu command") }
        ?? registered.map { NSLocalizedString($0.title, comment: "Menu command") } ?? id,
      action: #selector(execute(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = id
    item.identifier = NSUserInterfaceItemIdentifier("context." + id)
    if let state = states[id] {
      MenuCoordinator.apply(state, to: item)
    } else {
      item.isEnabled = false
    }
    return item
  }

  @objc private func execute(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    configuration?.registry.execute(id)
  }

  @objc private func openOnly() {
    if let openOnlyEntry { openOnlyAction?(openOnlyEntry) }
  }

  private func submenu(_ title: String, path: [String]) -> NSMenuItem {
    let parent = NSMenuItem(
      title: NSLocalizedString(title, comment: "Menu title"), action: nil, keyEquivalent: "")
    parent.identifier = NSUserInterfaceItemIdentifier("context." + title)
    let menu = NSMenu(title: title)
    menu.autoenablesItems = false
    for registered in configuration?.registry.commands ?? [] where registered.menuPath == path {
      menu.addItem(command(registered.id))
    }
    parent.submenu = menu
    parent.isEnabled = menu.items.contains(where: \.isEnabled)
    return parent
  }

  /// The default app comes first, then the others A to Z, then Other….
  private func openWithItem(_ entries: [FileEntry]) -> NSMenuItem {
    let parent = NSMenuItem(
      title: NSLocalizedString("Open With", comment: "Menu title"), action: nil, keyEquivalent: "")
    parent.identifier = NSUserInterfaceItemIdentifier("context.Open With")
    let menu = NSMenu(title: "Open With")
    menu.autoenablesItems = false
    let prefix = "file.openWith."
    let other = prefix + "other"
    let applications = (configuration?.registry.commands ?? [])
      .filter { $0.id.hasPrefix(prefix) && $0.id != other }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    let defaultPath = entries.first.flatMap { entry -> String? in
      guard entry.location.providerID == "local" else { return nil }
      return NSWorkspace.shared.urlForApplication(
        toOpen: URL(fileURLWithPath: entry.location.path))?.path
    }
    func application(_ registered: AppCommand, title: String? = nil) -> NSMenuItem {
      let item = command(registered.id, title: title)
      let icon = NSWorkspace.shared.icon(forFile: String(registered.id.dropFirst(prefix.count)))
      icon.size = NSSize(width: 16, height: 16)
      item.image = icon
      return item
    }
    if let preferred = applications.first(where: { $0.id == prefix + (defaultPath ?? "") }) {
      menu.addItem(
        application(
          preferred,
          title: String(
            format: NSLocalizedString("%@ (default)", comment: "Default app"), preferred.title)))
      menu.addItem(.separator())
    }
    for registered in applications where registered.id != prefix + (defaultPath ?? "") {
      menu.addItem(application(registered))
    }
    if !applications.isEmpty { menu.addItem(.separator()) }
    menu.addItem(command(other))
    parent.submenu = menu
    parent.isEnabled = menu.items.contains(where: \.isEnabled)
    return parent
  }

  /// A folder's children are read only if someone opens this submenu.
  private func contentsItem(_ folder: FileEntry) -> NSMenuItem {
    let parent = NSMenuItem(
      title: NSLocalizedString("Contents", comment: "Menu title"), action: nil, keyEquivalent: "")
    parent.identifier = NSUserInterfaceItemIdentifier("context.Contents")
    let menu = NSMenu(title: "Contents")
    menu.autoenablesItems = false
    menu.delegate = self
    parent.submenu = menu
    parent.representedObject = folder.location.path
    contentsPaths[ObjectIdentifier(menu)] = folder.location.path
    return parent
  }

  private var contentsPaths: [ObjectIdentifier: String] = [:]

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let path = contentsPaths[ObjectIdentifier(menu)], menu.items.isEmpty else { return }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let showHidden = configuration?.settings.showHidden == true
    let children =
      ((try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil,
        options: showHidden ? [] : [.skipsHiddenFiles])) ?? [])
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
    for child in children.prefix(Self.contentsLimit) {
      let item = NSMenuItem(
        title: child.lastPathComponent, action: #selector(openChild(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = child
      let icon = NSWorkspace.shared.icon(forFile: child.path)
      icon.size = NSSize(width: 16, height: 16)
      item.image = icon
      menu.addItem(item)
    }
    if children.count > Self.contentsLimit {
      let more = NSMenuItem(
        title: String(
          format: NSLocalizedString("%d more items", comment: "Context menu"),
          children.count - Self.contentsLimit),
        action: nil, keyEquivalent: "")
      more.isEnabled = false
      menu.addItem(more)
    }
    if children.isEmpty {
      let empty = NSMenuItem(
        title: NSLocalizedString("Empty", comment: "Context menu"), action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    }
  }

  @objc private func openChild(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL, let configuration else { return }
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    if values?.isDirectory == true, values?.isPackage != true {
      let location = Location(providerID: "local", path: url.path)
      Task { await configuration.browser.enterFolder(location, in: configuration.paneID) }
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  /// A row of color dots that turn a tag on or off for the selection.
  private func tagDots(_ tags: [FileTag]) -> NSMenuItem {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
    for tag in tags.prefix(7) {
      let id = "file.tag." + tag.name
      let button = NSButton(
        image: Self.dot(NSColor(tag.color.swatch), checked: states[id]?.isChecked == true),
        target: self, action: #selector(toggleTag(_:)))
      button.isBordered = false
      button.imagePosition = .imageOnly
      button.identifier = NSUserInterfaceItemIdentifier(id)
      button.setAccessibilityIdentifier("context." + id)
      button.setAccessibilityLabel(tag.name)
      button.toolTip = states[id]?.disabledReason ?? tag.name
      button.isEnabled = states[id]?.disabledReason == nil
      stack.addArrangedSubview(button)
    }
    stack.setFrameSize(stack.fittingSize)
    let item = NSMenuItem()
    item.view = stack
    return item
  }

  @objc private func toggleTag(_ sender: NSButton) {
    pendingCommand = sender.identifier?.rawValue
    sender.enclosingMenuItem?.menu?.cancelTracking()
  }

  /// The browser isn't the front window while a menu is open, so commands wait for it to close.
  func runPendingCommand() {
    if let pendingCommand { configuration?.registry.execute(pendingCommand) }
    pendingCommand = nil
  }

  private static func dot(_ color: NSColor, checked: Bool) -> NSImage {
    NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
      if checked {
        NSColor.labelColor.setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
        ring.lineWidth = 1.5
        ring.stroke()
      }
      return true
    }
  }
}
