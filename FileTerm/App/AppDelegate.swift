import AppKit
import FileTermCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let provider = LocalFileSystemProvider()
  private lazy var browser = BrowserModel(providers: [provider])
  private let volumeService = NativeVolumeService()
  private lazy var devices = DeviceModel(service: volumeService)
  private lazy var settings = AppSettings(suite: settingsSuite)
  private lazy var settingsCoordinator = SettingsCoordinator(settings: settings)
  private var browserWindow: NSWindow?
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
    context: { [unowned self] in
      CommandContext(
        hasBrowserWindow: browserWindow?.isVisible == true,
        hasKeyWindow: NSApp.keyWindow != nil, isLoading: browser.activePane.isLoading,
        sourceLocation: browser.activePane.location, targetLocation: browser.targetPane?.location,
        canGoBack: browser.activePane.canGoBack, canGoForward: browser.activePane.canGoForward,
        canGoUp: browser.activePane.canGoUp, canCoordinatePanes: browser.canCoordinatePanes,
        canEject: settings.isVisible(.devices) && devices.canEject
      )
    }
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    browser.onVisit = { [weak self] location in self?.settings.recordVisit(location) }
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
      NSWorkspace.didRenameVolumeNotification,
    ] {
      center.addObserver(self, selector: #selector(volumeChanged(_:)), name: name, object: nil)
    }
    menuCoordinator = MenuCoordinator(registry: registry)
    menuCoordinator?.install()
    showBrowser()
    let initialURL =
      ProcessInfo.processInfo.environment["FILETERM_INITIAL_DIRECTORY"]
      .map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    Task {
      let location = provider.location(for: initialURL)
      await browser.navigate(to: location, in: .first)
      await browser.navigate(to: location, in: .second)
      await devices.refresh()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showBrowser()
    return true
  }

  private func showBrowser() {
    if browserWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false
      )
      window.title = "FileTerm"
      window.identifier = NSUserInterfaceItemIdentifier("browserWindow")
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(
        rootView: BrowserView(
          browser: browser, settings: settings, registry: registry, localProvider: provider,
          devices: devices)
      )
      window.center()
      browserWindow = window
      applyWindowChrome()
    }
    browserWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate()
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
    guard let window = browserWindow else { return }
    let visible = settings.isVisible(.titleBar)
    window.titleVisibility = visible ? .visible : .hidden
    window.titlebarAppearsTransparent = !visible
    if visible {
      window.styleMask.remove(.fullSizeContentView)
    } else {
      window.styleMask.insert(.fullSizeContentView)
    }
  }

  @objc private func volumeChanged(_ notification: Notification) {
    let unmounted = notification.name == NSWorkspace.didUnmountNotification
    let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
    Task {
      await devices.refresh()
      guard unmounted, let url else { return }
      await browser.handleUnmount(
        at: url, home: provider.location(for: FileManager.default.homeDirectoryForCurrentUser))
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
          let id = browser.activePaneID
          Task {
            await self.browser.navigate(
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
          let id = browser.activePaneID
          Task { await self.browser.goBack(in: id) }
        }),
      AppCommand(
        id: "go.forward", title: "Forward", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow && $0.canGoForward && !$0.isLoading },
        disabledReason: {
          $0.isLoading ? "Wait for navigation to finish." : "There is no next folder in this pane."
        },
        handler: { [weak self] in
          guard let self else { return }
          let id = browser.activePaneID
          Task { await self.browser.goForward(in: id) }
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
          let id = browser.activePaneID
          Task { await self.browser.goUp(in: id) }
        }),
      AppCommand(
        id: "go.toFolder", title: "Go to Folder…", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { NotificationCenter.default.post(name: .fileTermGoToFolder, object: nil) }),
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
        handler: { [weak self] in Task { await self?.browser.clonePane() } }),
      AppCommand(
        id: "file.eject", title: "Eject", menuPath: ["File"],
        isEnabled: { $0.hasBrowserWindow && $0.canEject },
        disabledReason: { _ in "Select an ejectable volume in the Devices sidebar." },
        handler: { [weak self] in Task { await self?.devices.ejectSelected() } }),
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
      ("selectAll", "Select All", "a", #selector(NSText.selectAll(_:))),
    ] {
      commands.append(
        AppCommand(
          id: "edit.text.\(id)", title: title, menuPath: ["Edit"], shortcut: key,
          isEnabled: { _ in NSApp.keyWindow?.firstResponder is NSTextView },
          disabledReason: { _ in "Focus a text field to edit text." },
          handler: { NSApp.sendAction(action, to: nil, from: nil) }))
    }
    return commands + navigationCommands()
  }
}
