import AppKit
import FileTermCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let provider = LocalFileSystemProvider()
  private lazy var fallbackBrowser = BrowserModel(
    providers: [provider], viewPreferences: settings.viewPreferences)
  private var windows: [BrowserWindowController] = []
  private weak var lastBrowser: BrowserWindowController?
  private var currentWindow: BrowserWindowController? {
    windows.first { $0.window === NSApp.keyWindow } ?? windows.first {
      $0.window === NSApp.mainWindow
    }
      ?? lastBrowser ?? windows.last
  }
  private var browser: BrowserModel { currentWindow?.browser ?? fallbackBrowser }
  private var browserWindow: NSWindow? { currentWindow?.window }
  private let volumeService = NativeVolumeService()
  private lazy var fallbackDevices = DeviceModel(service: volumeService)
  private var devices: DeviceModel { currentWindow?.devices ?? fallbackDevices }
  private lazy var settings = AppSettings(suite: settingsSuite)
  private lazy var settingsCoordinator = SettingsCoordinator(
    settings: settings, registry: { [unowned self] in registry })
  private let folderWatcher = FolderWatcher()

  /// The browser window is in front with no dialog on top (Quick Open counts as part of the browser).
  private var browserIsFront: Bool {
    guard let window = browserWindow, window.isVisible else { return false }
    if let key = NSApp.keyWindow {
      if key === window { return window.attachedSheet == nil }
      if browser.isQuickOpenOpen, key.sheetParent === window { return true }
      return false
    }
    return window.attachedSheet == nil
  }

  /// Esc must keep working for sheets, popovers and text editing, so Quick Open only claims it
  /// when the browser window is active and nothing is being edited.
  private var canQuickOpen: Bool {
    guard let window = browserWindow, window.isVisible, window.attachedSheet == nil else {
      return false
    }
    if let key = NSApp.keyWindow, key !== window { return false }
    return !(window.firstResponder is NSText)
  }
  private var menuCoordinator: MenuCoordinator?

  private var settingsSuite: UserDefaults {
    if let name = ProcessInfo.processInfo.environment["FILETERM_SETTINGS_SUITE"],
      let suite = UserDefaults(suiteName: name)
    {
      return suite
    }
    return .standard
  }

  private lazy var registry = CommandRegistry(
    commands: makeCommands(),
    dynamicCommands: { [unowned self] in recentCommands() },
    shortcutOverrides: settings.shortcutOverrides,
    context: { [unowned self] in
      CommandContext(
        hasBrowserWindow: browserWindow?.isVisible == true,
        hasKeyWindow: NSApp.keyWindow != nil, isLoading: browser.activePane.isLoading,
        sourceLocation: browser.activePane.location, targetLocation: browser.targetPane?.location,
        canGoBack: browser.activePane.canGoBack, canGoForward: browser.activePane.canGoForward,
        canGoUp: browser.activePane.canGoUp, canCoordinatePanes: browser.canCoordinatePanes,
        canEject: settings.isVisible(.sidebar) && settings.isVisible(.devices) && devices.canEject,
        tabCount: browser.tabs(browser.activePaneID).tabs.count,
        selectionCount: browser.activePane.selection.count,
        canQuickOpen: canQuickOpen, isSearching: browser.activePane.searchScope != nil
      )
    }
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
      NSWorkspace.didRenameVolumeNotification,
    ] {
      center.addObserver(self, selector: #selector(volumeChanged(_:)), name: name, object: nil)
    }
    menuCoordinator = MenuCoordinator(registry: registry)
    menuCoordinator?.install()
    registry.onShortcutOverridesChanged = { [weak self] overrides in
      self?.settings.shortcutOverrides = overrides
      self?.menuCoordinator?.install()
    }
    folderWatcher.onChange = { [weak self] paths in self?.refreshWatched(paths) }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.settings.autoRefresh else { return }
        Task { for controller in self.windows { await controller.browser.refreshAll() } }
      }
    }
    let restore = settings.workspace.restoreWindows || settings.workspace.keepWindowsOnce
    let saved = restore ? settings.savedWindows : []
    settings.workspace.keepWindowsOnce = false
    Task {
      if saved.isEmpty {
        await newWindow()
      } else {
        for snapshot in saved { await newWindow(restoring: snapshot) }
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    settings.savedWindows = windows.map { $0.snapshot() }
    return .terminateNow
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showBrowser()
    return true
  }

  private func showBrowser() {
    if let controller = currentWindow {
      controller.window.makeKeyAndOrderFront(nil)
      NSApp.activate()
    } else {
      Task { await newWindow() }
    }
  }

  private func newWindow(restoring snapshot: WindowSnapshot? = nil) async {
    let model = BrowserModel(providers: [provider], viewPreferences: settings.viewPreferences)
    let deviceModel = DeviceModel(service: volumeService)
    let controller = BrowserWindowController(
      browser: model, devices: deviceModel, settings: settings,
      registry: registry, provider: provider, frame: snapshot?.frame)
    model.onVisit = { [weak self] location in
      self?.settings.recordVisit(location)
      self?.syncWatcher()
      self?.menuCoordinator?.refreshEnabling()
    }
    controller.onClose = { [weak self, weak controller] in
      guard let self, let controller else { return }
      windows.removeAll { $0 === controller }
      syncWatcher()
      if lastBrowser === controller { lastBrowser = windows.last }
      menuCoordinator?.refreshEnabling()
    }
    controller.onActivate = { [weak self, weak controller] in
      self?.lastBrowser = controller
      self?.menuCoordinator?.refreshEnabling()
    }
    windows.append(controller)
    lastBrowser = controller
    controller.window.makeKeyAndOrderFront(nil)
    NSApp.activate()
    let path =
      ProcessInfo.processInfo.environment["FILETERM_INITIAL_DIRECTORY"]
      ?? settings.workspace.startingDirectory
    let home = provider.location(for: FileManager.default.homeDirectoryForCurrentUser)
    let initial: Location
    do { initial = try await provider.resolveFolderPath(path) } catch {
      initial = home
      model.notice =
        "Starting Directory could not be opened. Opened Home instead. " + error.localizedDescription
    }
    if let snapshot {
      await model.restore(snapshot.browser, fallback: initial)
    } else {
      await model.navigate(to: initial, in: .first)
      await model.navigate(to: initial, in: .second)
    }
    await deviceModel.refresh()
    menuCoordinator?.refreshEnabling()
  }

  private func open(_ destination: StandardDestination) {
    do {
      let location = provider.location(for: try destination.url())
      devices.selectedVolumeID = nil
      let id = browser.activePaneID
      Task { await browser.navigate(to: location, in: id) }
    } catch { browser.notice = error.localizedDescription }
  }

  private func applyWindowChrome() {
    for controller in windows { controller.applyChrome(settings) }
  }

  @objc private func volumeChanged(_ notification: Notification) {
    let unmounted = notification.name == NSWorkspace.didUnmountNotification
    let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
    Task {
      for controller in windows {
        await controller.devices.refresh()
        if unmounted, let url {
          await controller.browser.handleUnmount(
            at: url, home: provider.location(for: FileManager.default.homeDirectoryForCurrentUser))
        }
      }
    }
  }

  private func recentCommands() -> [AppCommand] {
    if settings.recentFolders.isEmpty {
      return [
        AppCommand(
          id: "go.recent.empty", title: "No Recent Folders", menuPath: ["Go", "Recent Folders"],
          isEnabled: { _ in false }, disabledReason: { _ in "Visit a folder first." }, handler: {})
      ]
    }
    return settings.recentFolders.map { path in
      AppCommand(
        id: "go.recent.\(path)", title: path, menuPath: ["Go", "Recent Folders"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          devices.selectedVolumeID = nil
          let model = browser
          let id = model.activePaneID
          Task {
            await model.navigate(
              to: Location(providerID: self.provider.id, path: path), in: id)
          }
        })
    }
  }

  private func navigationCommands() -> [AppCommand] {
    var commands: [AppCommand] = [
      AppCommand(
        id: "go.back", title: "Back", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow && $0.canGoBack && !$0.isLoading },
        disabledReason: {
          $0.isLoading
            ? "Wait for navigation to finish." : "There is no previous folder in this pane."
        },
        handler: { [weak self] in
          guard let self else { return }
          let model = browser
          let id = model.activePaneID
          Task { await model.goBack(in: id) }
        }),
      AppCommand(
        id: "go.forward", title: "Forward", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow && $0.canGoForward && !$0.isLoading },
        disabledReason: {
          $0.isLoading ? "Wait for navigation to finish." : "There is no next folder in this pane."
        },
        handler: { [weak self] in
          guard let self else { return }
          let model = browser
          let id = model.activePaneID
          Task { await model.goForward(in: id) }
        }),
      AppCommand(
        id: "go.enclosingFolder", title: "Enclosing Folder", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow && $0.canGoUp && !$0.isLoading },
        disabledReason: {
          $0.isLoading
            ? "Wait for navigation to finish."
            : "This pane is at the filesystem root or has no folder."
        },
        handler: { [weak self] in
          guard let self else { return }
          let model = browser
          let id = model.activePaneID
          Task { await model.goUp(in: id) }
        }),
      AppCommand(
        id: "go.toFolder", title: "Go to Folder…", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(name: .fileTermGoToFolder, object: browser)
        }),
      AppCommand(
        id: "go.syncBrowsing", title: "Sync Browsing", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow && $0.canCoordinatePanes },
        disabledReason: { _ in "Open two panes and wait for navigation to finish." },
        isChecked: { [weak self] _ in self?.browser.syncBrowsing == true },
        handler: { [weak self] in self?.browser.syncBrowsing.toggle() }),
      AppCommand(
        id: "go.connections.empty", title: "No Connections", menuPath: ["Go", "Connections"],
        isEnabled: { _ in false }, disabledReason: { _ in "Connections will be available in M08." },
        handler: {}),
      AppCommand(
        id: "view.twoPanes", title: "Show Two Panes", menuPath: ["View"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        isChecked: { [weak self] _ in self?.browser.layout != .single },
        handler: { [weak self] in self?.browser.toggleTwoPanes() }),
      AppCommand(
        id: "view.swapPanes", title: "Swap Panes", menuPath: ["View"],
        isEnabled: { $0.hasBrowserWindow && $0.canCoordinatePanes },
        disabledReason: { _ in "Open two panes and wait for navigation to finish." },
        handler: { [weak self] in self?.browser.swapPanes() }),
      AppCommand(
        id: "view.clonePane", title: "Clone Pane", menuPath: ["View"],
        isEnabled: { $0.hasBrowserWindow && $0.canCoordinatePanes },
        disabledReason: { _ in "Open two panes and wait for navigation to finish." },
        handler: { [weak self] in
          guard let model = self?.browser else { return }
          Task { await model.clonePane() }
        }),
      AppCommand(
        id: "file.eject", title: "Eject", menuPath: ["File"],
        isEnabled: { $0.hasBrowserWindow && $0.canEject },
        disabledReason: { _ in "Select an ejectable volume in the Devices sidebar." },
        handler: { [weak self] in
          guard let model = self?.devices else { return }
          Task { await model.ejectSelected() }
        }),
    ]
    for layout in PaneLayout.allCases {
      let title =
        switch layout {
        case .single: "Single Pane"
        case .vertical: "Vertical — Side by Side"
        case .horizontal: "Horizontal — Stacked"
        }
      commands.append(
        AppCommand(
          id: "view.\(layout.rawValue)", title: title, menuPath: ["View"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          isChecked: { [weak self] _ in self?.browser.layout == layout },
          handler: { [weak self] in self?.browser.setLayout(layout) }))
    }
    for destination in StandardDestination.allCases {
      commands.append(
        AppCommand(
          id: destination.commandID, title: destination.rawValue, menuPath: ["Go"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in self?.open(destination) }))
    }
    for chrome in BrowserChrome.allCases {
      commands.append(
        AppCommand(
          id: chrome.commandID, title: "Show \(chrome.title)", menuPath: ["View"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          isChecked: { [weak self] _ in self?.settings.isVisible(chrome) == true },
          handler: { [weak self] in
            self?.settings.toggle(chrome)
            if chrome == .devices { self?.devices.selectedVolumeID = nil }
            self?.applyWindowChrome()
          }))
    }
    return commands
  }

  private func makeCommands() -> [AppCommand] {
    var commands: [AppCommand] = [
      AppCommand(
        id: "app.about", title: "About FileTerm", menuPath: ["FileTerm"], isEnabled: { _ in true },
        disabledReason: { _ in "" },
        handler: {
          NSApp.orderFrontStandardAboutPanel(nil)
        }
      ),
      AppCommand(
        id: "app.settings", title: "Settings…", menuPath: ["FileTerm"], shortcut: ",",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in
          self?.settingsCoordinator.show()
        }
      ),
      AppCommand(
        id: "app.hide", title: "Hide FileTerm", menuPath: ["FileTerm"], shortcut: "h",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: {
          NSApp.hide(nil)
        }
      ),
      AppCommand(
        id: "app.quit", title: "Quit FileTerm", menuPath: ["FileTerm"], shortcut: "q",
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: {
          NSApp.terminate(nil)
        }
      ),
      AppCommand(
        id: "file.showBrowser", title: "Show Browser Window", menuPath: ["File"],
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in
          self?.showBrowser()
        }
      ),
      AppCommand(
        id: "file.close", title: "Close Window", menuPath: ["File"], shortcut: "w",
        shortcutModifiers: [.command, .shift],
        isEnabled: { $0.hasKeyWindow }, disabledReason: { _ in "No window is open." },
        handler: {
          NSApp.keyWindow?.performClose(nil)
        }
      ),
      AppCommand(
        id: "window.minimize", title: "Minimize", menuPath: ["Window"], shortcut: "m",
        isEnabled: { _ in NSApp.keyWindow?.styleMask.contains(.miniaturizable) == true },
        disabledReason: { _ in "This window cannot be minimized." },
        handler: {
          NSApp.keyWindow?.performMiniaturize(nil)
        }
      ),
      AppCommand(
        id: "window.zoom", title: "Zoom", menuPath: ["Window"],
        isEnabled: { _ in NSApp.keyWindow?.styleMask.contains(.resizable) == true },
        disabledReason: { _ in "This window cannot be resized." },
        handler: {
          NSApp.keyWindow?.performZoom(nil)
        }
      ),
    ]
    for panel in PlaceholderPanel.allCases {
      commands.append(
        AppCommand(
          id: panel.commandID, title: "Show/Hide \(panel.rawValue)", menuPath: ["View"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          isChecked: { [weak self] _ in self?.settings.isVisible(panel) == true },
          handler: { [weak self] in self?.settings.toggle(panel) }
        ))
    }
    for (id, title, key, action) in [
      ("cut", "Cut", "x", #selector(NSText.cut(_:))),
      ("copy", "Copy", "c", #selector(NSText.copy(_:))),
      ("paste", "Paste", "v", #selector(NSText.paste(_:))),
    ] {
      commands.append(
        AppCommand(
          id: "edit.text.\(id)", title: title, menuPath: ["Edit"], shortcut: key,
          isEnabled: { _ in NSApp.keyWindow?.firstResponder is NSTextView },
          disabledReason: { _ in "Focus a text field to edit text." },
          handler: { NSApp.sendAction(action, to: nil, from: nil) }))
    }
    return commands + navigationCommands() + workspaceCommands() + selectionSearchCommands()
  }

  // MARK: Selection, search and quick commands (M03)

  private func syncWatcher() {
    guard settings.autoRefresh else {
      folderWatcher.watch([])
      return
    }
    var paths: Set<String> = []
    for controller in windows {
      for id in PaneID.allCases {
        for tab in controller.browser.tabs(id).tabs {
          if let location = tab.location, location.providerID == provider.id {
            paths.insert(location.path)
          }
        }
      }
    }
    folderWatcher.watch(paths)
  }

  private func refreshWatched(_ changed: Set<String>) {
    Task {
      for controller in windows {
        for id in PaneID.allCases {
          for tab in controller.browser.tabs(id).tabs {
            if let path = tab.location?.path, changed.contains(path) { await tab.refresh() }
          }
        }
      }
    }
  }

  private func setShowHidden(_ value: Bool) {
    settings.showHidden = value
    Task { for controller in windows { await controller.browser.setShowHidden(value) } }
  }

  private func selectionSearchCommands() -> [AppCommand] {
    let noWindow: (CommandContext) -> String = { _ in "Open the browser window first." }
    let available: (CommandContext) -> Bool = { $0.hasBrowserWindow }
    let inBrowser: (CommandContext) -> Bool = { [weak self] context in
      context.hasBrowserWindow && self?.browserIsFront == true
    }
    let nothingSelected: (CommandContext) -> String = { _ in "Nothing is selected." }
    func placeholder(
      _ id: String, _ title: String, _ shortcut: Shortcut, _ reason: String
    ) -> AppCommand {
      AppCommand(
        id: id, title: title, menuPath: ["File"], shortcut: shortcut.key,
        shortcutModifiers: shortcut.modifiers, isEnabled: { _ in false },
        disabledReason: { _ in reason }, handler: {})
    }
    return [
      AppCommand(
        id: "edit.selectAll", title: "Select All", menuPath: ["Edit"], shortcut: "a",
        isEnabled: { context in
          NSApp.keyWindow?.firstResponder is NSText || inBrowser(context)
        },
        disabledReason: noWindow,
        handler: { [weak self] in
          guard let self else { return }
          if !browser.isQuickOpenOpen,
            let first = NSApp.keyWindow?.firstResponder, first is NSText
          {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
          } else {
            browser.activePane.selectAll()
          }
        }),
      AppCommand(
        id: "edit.deselectAll", title: "Deselect All", menuPath: ["Edit"], shortcut: "a",
        shortcutModifiers: [.command, .shift],
        isEnabled: { $0.hasBrowserWindow && $0.selectionCount > 0 },
        disabledReason: { $0.hasBrowserWindow ? "Nothing is selected." : "Open the browser window first." },
        handler: { [weak self] in self?.browser.activePane.deselectAll() }),
      AppCommand(
        id: "edit.invertSelection", title: "Invert Selection", menuPath: ["Edit"], shortcut: "i",
        shortcutModifiers: [.command, .shift],
        isEnabled: { $0.hasBrowserWindow && $0.sourceLocation != nil }, disabledReason: noWindow,
        handler: { [weak self] in self?.browser.activePane.invertSelection() }),
      AppCommand(
        id: "select.quick", title: "Quick Select…", menuPath: ["Edit"], shortcut: "s",
        isEnabled: { context in inBrowser(context) && context.sourceLocation != nil },
        disabledReason: { _ in "Open a folder in the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(name: .fileTermQuickSelect, object: browser)
        }),
      AppCommand(
        id: "quickOpen", title: "Quick Open…", menuPath: ["Go"], shortcut: Shortcut.escape,
        shortcutModifiers: [],
        isEnabled: { $0.hasBrowserWindow && $0.canQuickOpen && !$0.isSearching },
        disabledReason: { context in
          context.isSearching
            ? "Close the search first." : "Quick Open is unavailable while editing text or in a dialog."
        },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(name: .fileTermQuickOpen, object: browser)
        }),
      AppCommand(
        id: "file.find", title: "Find…", menuPath: ["File"], shortcut: "f",
        isEnabled: { context in inBrowser(context) && context.sourceLocation != nil },
        disabledReason: { _ in "Open a folder in the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(name: .fileTermFind, object: browser)
        }),
      AppCommand(
        id: "file.closeSearch", title: "Close Search", menuPath: ["File"], shortcut: "f",
        shortcutModifiers: [.command, .option],
        isEnabled: { $0.hasBrowserWindow && $0.isSearching },
        disabledReason: { _ in "No search is open." },
        handler: { [weak self] in self?.browser.activePane.closeSearch() }),
      AppCommand(
        id: "view.showHidden", title: "Show Hidden Items", menuPath: ["View"], shortcut: ".",
        shortcutModifiers: [.command, .shift], isEnabled: available, disabledReason: noWindow,
        isChecked: { [weak self] _ in self?.settings.showHidden == true },
        handler: { [weak self] in
          guard let self else { return }
          setShowHidden(!settings.showHidden)
        }),
      AppCommand(
        id: "view.refresh", title: "Refresh", menuPath: ["View"], shortcut: "r",
        isEnabled: { $0.hasBrowserWindow && $0.sourceLocation != nil }, disabledReason: noWindow,
        handler: { [weak self] in
          guard let model = self?.browser else { return }
          Task { await model.refreshAll() }
        }),
      AppCommand(
        id: "view.autoRefresh", title: "Auto-Refresh", menuPath: ["View"],
        isEnabled: available, disabledReason: noWindow,
        isChecked: { [weak self] _ in self?.settings.autoRefresh == true },
        handler: { [weak self] in
          guard let self else { return }
          settings.autoRefresh.toggle()
          syncWatcher()
        }),
      placeholder(
        "file.newFolder", "New Folder", DefaultShortcuts.newFolder,
        "Creating folders arrives in M04."),
      placeholder(
        "file.newFolderWithSelection", "New Folder With Selection",
        DefaultShortcuts.newFolderWithSelection, "Creating folders arrives in M04."),
      placeholder(
        "file.newFile", "New File", DefaultShortcuts.newFile, "Creating files arrives in M04."),
      placeholder("file.open", "Open", DefaultShortcuts.open, "Opening items arrives in M04."),
      placeholder(
        "file.quickLook", "Quick Look", DefaultShortcuts.quickLook,
        "Quick Look arrives in M05."),
    ]
  }
  private func workspaceCommands() -> [AppCommand] {
    let noWindow: (CommandContext) -> String = { _ in "Open the browser window first." }
    let available: (CommandContext) -> Bool = { $0.hasBrowserWindow }
    var commands: [AppCommand] = [
      AppCommand(
        id: "file.newWindow", title: "New FileTerm Window", menuPath: ["File"], shortcut: "n",
        isEnabled: { _ in true }, disabledReason: noWindow,
        handler: { [weak self] in Task { await self?.newWindow() } }),
      AppCommand(
        id: "file.newTab", title: "New Tab", menuPath: ["File"], shortcut: "t",
        isEnabled: available, disabledReason: noWindow,
        handler: { [weak self] in
          guard let self else { return }
          browser.newTab(in: browser.activePaneID)
        }),
      AppCommand(
        id: "file.closeTab", title: "Close Tab", menuPath: ["File"], shortcut: "w",
        isEnabled: { $0.hasKeyWindow }, disabledReason: noWindow,
        handler: { [weak self] in
          guard let self else { return }
          if NSApp.keyWindow !== browserWindow {
            NSApp.keyWindow?.performClose(nil)
            return
          }
          if !browser.closeTab(in: browser.activePaneID) { browserWindow?.performClose(nil) }
        }),
      AppCommand(
        id: "file.closeOtherTabs", title: "Close Other Tabs", menuPath: ["File"],
        isEnabled: { $0.hasBrowserWindow && $0.tabCount > 1 },
        disabledReason: { _ in "This pane has only one tab." },
        handler: { [weak self] in
          guard let self else { return }
          browser.closeOtherTabs(in: browser.activePaneID)
        }),
      AppCommand(
        id: "window.pinView", title: "Pin View", menuPath: ["Window"],
        isEnabled: { $0.hasBrowserWindow && !$0.isLoading && $0.sourceLocation != nil },
        disabledReason: { _ in "Open a folder and wait for navigation to finish." },
        isChecked: { [weak self] _ in self?.browser.activePane.isPinned == true },
        handler: { [weak self] in self?.browser.activePane.isPinned.toggle() }),
      AppCommand(
        id: "window.bringAll", title: "Bring All to Front", menuPath: ["Window"],
        isEnabled: { [weak self] _ in self?.windows.isEmpty == false }, disabledReason: noWindow,
        handler: { NSApp.arrangeInFront(nil) }),
      AppCommand(
        id: "app.quitKeepWindows", title: "Quit and Keep Windows", menuPath: ["FileTerm"],
        shortcut: "q", shortcutModifiers: [.command, .option],
        isEnabled: { _ in true }, disabledReason: noWindow,
        handler: { [weak self] in
          self?.settings.workspace.keepWindowsOnce = true
          NSApp.terminate(nil)
        }),
    ]
    for mode in FileViewMode.allCases {
      commands.append(
        AppCommand(
          id: "view.as" + mode.rawValue, title: "as " + mode.rawValue, menuPath: ["View"],
          isEnabled: available, disabledReason: noWindow,
          isChecked: { [weak self] _ in self?.browser.activePane.viewOptions.mode == mode },
          handler: { [weak self] in self?.browser.activePane.viewOptions.mode = mode }))
    }
    for field in FileSortField.allCases {
      commands.append(
        AppCommand(
          id: "view.sort." + field.rawValue, title: field.rawValue, menuPath: ["View", "Sort by"],
          isEnabled: available, disabledReason: noWindow,
          isChecked: { [weak self] _ in self?.browser.activePane.viewOptions.sortField == field },
          handler: { [weak self] in self?.browser.activePane.viewOptions.sortField = field }))
    }
    commands.append(
      AppCommand(
        id: "view.descending", title: "Descending Order", menuPath: ["View", "Sort by"],
        isEnabled: available, disabledReason: noWindow,
        isChecked: { [weak self] _ in self?.browser.activePane.viewOptions.descending == true },
        handler: { [weak self] in self?.browser.activePane.viewOptions.descending.toggle() }))
    for field in FileGroupField.allCases {
      commands.append(
        AppCommand(
          id: "view.group." + field.rawValue, title: field.rawValue,
          menuPath: ["View", "Group by"],
          isEnabled: available, disabledReason: noWindow,
          isChecked: { [weak self] _ in self?.browser.activePane.viewOptions.groupField == field },
          handler: { [weak self] in self?.browser.activePane.viewOptions.groupField = field }))
    }
    for (id, title, sheet) in [
      ("view.options", "Show View Options", BrowserOptionsSheet.viewOptions),
      ("view.customizeToolbar", "Customize Toolbar…", .toolbar),
      ("view.sidebarEditor", "Show Sidebar Editor", .sidebar),
    ] {
      commands.append(
        AppCommand(
          id: id, title: title, menuPath: ["View"], isEnabled: available, disabledReason: noWindow,
          handler: { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
              name: .fileTermBrowserOptions, object: browser, userInfo: ["kind": sheet.rawValue])
          }))
    }
    commands.append(
      AppCommand(
        id: "view.saveDefaults", title: "Save View Settings as Defaults", menuPath: ["View"],
        isEnabled: available, disabledReason: noWindow,
        handler: { [weak self] in self?.browser.activePane.saveViewSettingsAsDefaults() }))
    commands.append(
      AppCommand(
        id: "view.restoreDefaults", title: "Restore Default View Settings", menuPath: ["View"],
        isEnabled: available, disabledReason: noWindow,
        handler: { [weak self] in self?.browser.activePane.restoreDefaultViewSettings() }))
    for (step, title, key) in [(-1, "Previous Tab", "["), (1, "Next Tab", "]")] {
      commands.append(
        AppCommand(
          id: step < 0 ? "window.previousTab" : "window.nextTab", title: title,
          menuPath: ["Window"], shortcut: key, shortcutModifiers: [.command, .shift],
          isEnabled: { $0.hasBrowserWindow && $0.tabCount > 1 },
          disabledReason: { _ in "This pane has only one tab." },
          handler: { [weak self] in
            guard let self else { return }
            browser.cycleTab(step, in: browser.activePaneID)
          }))
    }
    for index in 0..<5 {
      commands.append(
        AppCommand(
          id: "window.tab\(index + 1)", title: "Select Tab \(index + 1)", menuPath: ["Window"],
          shortcut: String(index + 1),
          isEnabled: { $0.hasBrowserWindow && $0.tabCount > index },
          disabledReason: { _ in "This pane does not have tab \(index + 1)." },
          handler: { [weak self] in
            guard let self else { return }
            browser.selectTab(at: index, in: browser.activePaneID)
          }))
    }
    return commands
  }

}
