import AppKit
import FileTermCore
import SwiftTerm
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let provider = LocalFileSystemProvider()
  private lazy var providerRegistry = ProviderRegistry(providers: [provider])
  private lazy var fallbackBrowser = BrowserModel(
    registry: providerRegistry, viewPreferences: settings.viewPreferences)
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
  private lazy var connections = ConnectionCoordinator(
    settings: settings, registry: providerRegistry)
  private lazy var settingsCoordinator = SettingsCoordinator(
    settings: settings, registry: { [unowned self] in registry }, cloudFiles: cloudFiles)
  private lazy var cloudFiles: CloudFileActions = {
    let actions = CloudFileActions()
    actions.onNotice = { [unowned self] in browser.notice = $0 }
    return actions
  }()
  /// Open and reveal requests that arrive before the first window exists.
  private var pendingOpenURLs: [URL] = []
  private var isReadyToOpenURLs = false
  private let folderWatcher = FolderWatcher()
  private let fileOperations = FileOperationCoordinator()
  private let filePreviews = FilePreviewCoordinator()
  private let fileUtilities = FileUtilityCoordinator()
  private lazy var toolRunner = ToolRunner(fileOperations: fileOperations)
  private lazy var gitRunner = GitRunner(fileOperations: fileOperations)
  private lazy var remoteEdits = RemoteEditCoordinator(fileOperations: fileOperations)
  private let updates = UpdateChecker()
  private let onboarding = OnboardingCoordinator()

  /// The browser window is in front with no dialog on top (Quick Open counts as part of the browser).
  private var browserIsFront: Bool {
    guard let window = browserWindow, window.isVisible else { return false }
    if window.firstResponder is TerminalView { return false }
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
    return !(window.firstResponder is NSText) && !(window.firstResponder is TerminalView)
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
    dynamicCommands: { [unowned self] in
      recentCommands() + connectionCommands() + favoriteCommands() + savedWorkspaceCommands()
        + syncFavoriteCommands()
        + toolCommands() + openWithCommands()
    },
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

  /// Hosted tests can start before `applicationDidFinishLaunching`, so the menus are set up earlier.
  func applicationWillFinishLaunching(_ notification: Notification) {
    menuCoordinator = MenuCoordinator(registry: registry)
    menuCoordinator?.install()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    ThemeLibrary.apply(settings.theme)
    NSApp.registerServicesMenuSendTypes(ServiceTypes.files + [.string], returnTypes: [])
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
      NSWorkspace.didRenameVolumeNotification,
    ] {
      center.addObserver(self, selector: #selector(volumeChanged(_:)), name: name, object: nil)
    }
    registry.onShortcutOverridesChanged = { [weak self] overrides in
      self?.settings.shortcutOverrides = overrides
      self?.menuCoordinator?.install()
    }
    NotificationCenter.default.addObserver(
      forName: .init("FileTerm.BeginRename"), object: nil, queue: .main
    ) { [weak self] notification in
      guard let pane = notification.object as? PaneModel else { return }
      MainActor.assumeIsolated {
        guard let self,
          let controller = self.windows.first(where: { controller in
            PaneID.allCases.contains { id in
              controller.browser.tabs(id).tabs.contains { $0 === pane }
            }
          })
        else { return }
        self.fileOperations.startRename(pane, window: controller.window)
      }
    }
    NotificationCenter.default.addObserver(
      forName: .fileTermDropFiles, object: nil, queue: .main
    ) { [weak self] notification in
      guard let pane = notification.object as? PaneModel,
        let urls = notification.userInfo?["urls"] as? [URL],
        let optionPressed = notification.userInfo?["optionPressed"] as? Bool
      else { return }
      MainActor.assumeIsolated {
        guard let self else { return }
        let controller = self.windows.first { controller in
          PaneID.allCases.contains { id in
            controller.browser.tabs(id).tabs.contains { $0 === pane }
          }
        }
        let confirm = self.settings.askBeforeDrag
        Task {
          await self.fileOperations.drop(
            urls, onto: pane, confirm: confirm, optionPressed: optionPressed,
            window: controller?.window)
        }
      }
    }
    NotificationCenter.default.addObserver(
      forName: .fileTermRenamePreset, object: nil, queue: .main
    ) { [weak self] notification in
      guard let pane = notification.object as? PaneModel,
        let id = notification.userInfo?["presetID"] as? UUID
      else { return }
      MainActor.assumeIsolated {
        guard let self, pane.selection.count > 1,
          let preset = self.settings.renamePresets.first(where: { $0.id == id })
        else { return }
        self.openBatchRename(pane, preset: preset)
      }
    }
    fileOperations.preferences = { [weak self] in self?.settings.transfers ?? TransferPreferences()
    }
    fileOperations.transfers.preferences = settings.transfers
    fileOperations.onBatchRename = { [weak self] pane in self?.openBatchRename(pane) }
    fileOperations.detectsAppOnDelete = { [weak self] in self?.settings.detectAppOnDelete == true }
    fileOperations.archiveOpenBehavior = { [weak self] in
      guard let self, settings.handleArchives else { return .system }
      return settings.archivesAsFolders ? .browse : .extract
    }
    fileOperations.registry = providerRegistry
    fileOperations.describe = { [weak self] in self?.connections.describe($0) ?? $0.path }
    fileOperations.refresh = { [weak self] in
      guard let self else { return }
      for controller in windows {
        await controller.browser.refreshAll()
        for id in PaneID.allCases {
          for pane in controller.browser.tabs(id).tabs {
            fileOperations.bindRename(pane, window: controller.window)
          }
        }
      }
    }
    filePreviews.onMetadataChange = { [weak self] in
      Task { [weak self] in
        guard let self else { return }
        for controller in self.windows { await controller.browser.refreshAll() }
      }
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
      isReadyToOpenURLs = true
      if !pendingOpenURLs.isEmpty {
        await reveal(pendingOpenURLs)
        pendingOpenURLs = []
      }
      offerFavoritesImport()
      if OnboardingCoordinator.shouldShow(
        alreadyShown: settings.onboardingShown, environment: ProcessInfo.processInfo.environment)
      {
        settings.onboardingShown = true
        onboarding.show()
      }
      if settings.automaticUpdateChecks { await updates.check(reportsUpToDate: false) }
    }
  }

  /// Other apps' Reveal and Show in Finder requests arrive here when FileTerm is the default file
  /// viewer. An open request looks the same, so a folder opens and a file is selected in its folder.
  func application(_ application: NSApplication, open urls: [URL]) {
    guard isReadyToOpenURLs else {
      pendingOpenURLs += urls
      return
    }
    Task { await reveal(urls) }
  }

  private func reveal(_ urls: [URL]) async {
    if windows.isEmpty { await newWindow() }
    let requests = RevealRequest.plan(paths: urls.filter(\.isFileURL).map(\.path)) { path in
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        && isDirectory.boolValue
    }
    let model = browser
    let id = model.activePaneID
    for (index, request) in requests.enumerated() {
      if index > 0 { model.newTab(in: id) }
      let folder = provider.location(for: URL(fileURLWithPath: request.folder, isDirectory: true))
      await model.navigate(to: folder, in: id)
      // Match by name: the listing's paths are normalized and may differ from the request's.
      let pane = model.pane(id)
      let names = Set(request.selected.map { ($0 as NSString).lastPathComponent })
      pane.selection = Set(pane.visibleEntries.filter { names.contains($0.name) }.map(\.id))
    }
    showBrowser()
  }

  /// The first run that finds ForkLift 3 favorites offers to import them.
  private func offerFavoritesImport() {
    guard !settings.favoritesImportOffered,
      FileManager.default.fileExists(atPath: FavoritesImport.forkLift3Path)
    else { return }
    settings.favoritesImportOffered = true
    NotificationCenter.default.post(
      name: .fileTermBrowserOptions, object: browser,
      userInfo: ["kind": BrowserOptionsSheet.favoritesImport.rawValue])
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard FilePreviewContentView.confirmTermination() else { return .terminateCancel }
    if fileOperations.isBusy {
      let alert = NSAlert()
      alert.messageText = "Transfers are still active"
      alert.informativeText =
        "Wait for transfers to finish or cancel them in Activities before quitting."
      alert.addButton(withTitle: "Keep FileTerm Open")
      alert.runModal()
      return .terminateCancel
    }
    settings.savedWindows = windows.map { $0.snapshot() }
    for controller in windows { controller.terminal.closeAll() }
    FileOperationCoordinator.removeTemporaryDownloads()
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

  /// Closes archives opened as folders once no tab in any window shows them.
  private func pruneArchives() {
    fileOperations.pruneArchives(
      inUse: windows.reduce(into: Set<String>()) { $0.formUnion($1.browser.openProviderIDs) })
  }

  private func newWindow(restoring snapshot: WindowSnapshot? = nil) async {
    let model = BrowserModel(
      registry: providerRegistry, viewPreferences: settings.viewPreferences)
    let deviceModel = DeviceModel(service: volumeService)
    let controller = BrowserWindowController(
      browser: model, devices: deviceModel, settings: settings,
      registry: registry, provider: provider, frame: snapshot?.frame,
      terminalPanel: snapshot?.terminal, transfers: fileOperations.transfers,
      connections: connections, cloudFiles: cloudFiles)
    model.onVisit = { [weak self, weak controller, weak model] location in
      self?.settings.recordVisit(location)
      self?.syncWatcher()
      self?.menuCoordinator?.refreshEnabling()
      self?.pruneArchives()
      if let model {
        for id in PaneID.allCases {
          for pane in model.tabs(id).tabs {
            self?.fileOperations.bindRename(pane, window: controller?.window)
          }
        }
      }
    }
    model.onOpenFile = { [weak self, weak model] entry in
      guard let self, let model else { return false }
      return fileOperations.openArchive(entry, in: model)
    }
    controller.onClose = { [weak self, weak controller] in
      guard let self, let controller else { return }
      windows.removeAll { $0 === controller }
      pruneArchives()
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
    for id in PaneID.allCases {
      for pane in model.tabs(id).tabs { fileOperations.bindRename(pane, window: controller.window) }
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
    if unmounted, let url { connections.handleUnmount(at: url) }
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

  /// View › Text Encoding: for the active pane's FTP or SFTP connection.
  private func textEncodingCommands() -> [AppCommand] {
    TextEncoding.names.map { name in
      AppCommand(
        id: "view.textEncoding.\(name)", title: name, menuPath: ["View", "Text Encoding"],
        isEnabled: { [weak self] context in
          context.sourceLocation.flatMap { self?.connections.textEncoding(for: $0) } != nil
        },
        disabledReason: { _ in "Only for FTP and SFTP connections." },
        isChecked: { [weak self] context in
          context.sourceLocation.flatMap { self?.connections.textEncoding(for: $0) } == name
        },
        handler: { [weak self] in
          guard let self, let location = browser.activePane.location else { return }
          let model = browser
          Task { await self.connections.setTextEncoding(name, for: location, in: model) }
        })
    }
  }

  private func connectionCommands() -> [AppCommand] {
    let path = ["Go", "Connections"]
    var commands: [AppCommand] = []
    for connection in connections.open {
      let name = "\(connection.profile.displayName) — \(connection.profile.server)"
      commands.append(
        AppCommand(
          id: "go.connections.open.\(connection.id)", title: name, menuPath: path,
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in
            guard let self else { return }
            let model = browser
            Task { await self.connections.reveal(connection, in: model) }
          }))
    }
    let openIDs = Set(connections.open.map(\.id))
    for profile in connections.savedProfiles where !openIDs.contains(profile.id) {
      commands.append(
        AppCommand(
          id: "go.connections.saved.\(profile.id)", title: profile.displayName, menuPath: path,
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in
            guard let self else { return }
            let model = browser
            Task {
              do { try await self.connections.connectAndReveal(profile, in: model) } catch {
                model.notice = error.localizedDescription
              }
            }
          }))
    }
    for profile in connections.profiles {
      commands.append(
        AppCommand(
          id: "go.connections.edit.\(profile.id)", title: "Edit \(profile.displayName)…",
          menuPath: path + ["Edit Saved Connection"], isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
              name: .fileTermConnect, object: browser, userInfo: ["profileID": profile.id])
          }))
    }
    for connection in connections.open {
      commands.append(
        AppCommand(
          id: "go.connections.disconnect.\(connection.id)",
          title: "Disconnect \(connection.profile.displayName)",
          menuPath: path + ["Disconnect"], isEnabled: { _ in true },
          disabledReason: { _ in "" },
          handler: { [weak self] in
            guard let self else { return }
            let model = browser
            let home = self.provider.location(for: FileManager.default.homeDirectoryForCurrentUser)
            Task {
              do { try await self.connections.disconnect(connection, in: model, home: home) } catch
              {
                model.notice = error.localizedDescription
              }
            }
          }))
    }
    commands += textEncodingCommands()
    if commands.isEmpty {
      commands.append(
        AppCommand(
          id: "go.connections.empty", title: "No Connections", menuPath: path,
          isEnabled: { _ in false },
          disabledReason: { _ in "Use Go › Connect… to open a connection." }, handler: {}))
    }
    return commands
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
        id: "commands.sync", title: "Sync to…", menuPath: ["Commands"],
        isEnabled: { $0.hasBrowserWindow && $0.canCoordinatePanes },
        disabledReason: { _ in "Open two panes side by side and wait for navigation to finish." },
        handler: { [weak self] in self?.openSync() }),
      AppCommand(
        id: "commands.manageTools", title: "Manage Tools…", menuPath: ["Commands"],
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in self?.settingsCoordinator.show(.tools) }),
      AppCommand(
        id: "go.connect", title: "Connect…", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(name: .fileTermConnect, object: browser)
        }),
      AppCommand(
        id: "go.favorites.manage", title: "Manage Favorites…", menuPath: ["Go"],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in
          guard let self else { return }
          NotificationCenter.default.post(
            name: .fileTermBrowserOptions, object: browser,
            userInfo: ["kind": BrowserOptionsSheet.favorites.rawValue])
        }),
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
        id: "app.checkForUpdates", title: "Check for Updates…", menuPath: ["FileTerm"],
        isEnabled: { _ in true }, disabledReason: { _ in "" },
        handler: { [weak self] in
          guard let self else { return }
          Task { await self.updates.check(reportsUpToDate: true) }
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
        id: "app.emptyTrash", title: "Empty Trash…", menuPath: ["FileTerm"],
        isEnabled: { [weak self] _ in self?.fileOperations.trashItemCount() != 0 },
        disabledReason: { _ in "The Trash is empty." },
        handler: { [weak self] in self?.fileOperations.emptyTrash() }
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
          isEnabled: { [weak self] _ in
            if NSApp.keyWindow?.firstResponder is NSTextView { return true }
            if NSApp.keyWindow?.firstResponder is TerminalView { return id != "cut" }
            guard let self, browserIsFront else { return false }
            if id == "copy" { return !browser.activePane.selection.isEmpty }
            if id == "paste" {
              return browser.activePane.location != nil && !fileOperations.clipboardURLs.isEmpty
            }
            return false
          },
          disabledReason: { _ in "Select files, copy file URLs, or focus a text field." },
          handler: { [weak self] in
            if NSApp.keyWindow?.firstResponder is NSTextView
              || NSApp.keyWindow?.firstResponder is TerminalView
            {
              NSApp.sendAction(action, to: nil, from: nil)
            } else if let self {
              if id == "copy" { fileOperations.copy(browser.activePane) }
              if id == "paste" {
                fileOperations.transfer(
                  browser, move: false, clipboard: true, window: browserWindow)
              }
            }
          }))
    }
    return commands + navigationCommands() + workspaceCommands() + selectionSearchCommands()
      + fileOperationCommands() + metadataUtilityCommands() + terminalCommands()
  }

  // MARK: Built-in terminal (M06)

  private func terminalCommands() -> [AppCommand] {
    var commands = [
      AppCommand(
        id: "view.terminal", title: "Show Terminal", menuPath: ["View"],
        shortcut: "`", shortcutModifiers: [.control],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open a browser window first." },
        isChecked: { [weak self] _ in self?.currentWindow?.terminal.panel.isVisible == true },
        handler: { [weak self] in self?.currentWindow?.terminal.toggleVisibility() }),
      AppCommand(
        id: "terminal.focus", title: "Focus Terminal / Pane", menuPath: ["View", "Terminal"],
        shortcut: "`", shortcutModifiers: [.control, .option],
        isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open a browser window first." },
        handler: { [weak self] in self?.currentWindow?.terminal.toggleFocus() }),
    ]
    for (id, title) in [
      ("link", "Link Terminal to Pane"), ("reverseSync", "Follow Terminal Directory"),
      ("sync", "Sync Terminal Now"), ("reveal", "Reveal Terminal Directory in Pane"),
      ("insertSelection", "Insert Selected Paths in Terminal"),
      ("openSSH", "Open SSH Session for Connected Host"),
      ("clear", "Clear Terminal"), ("find", "Find in Terminal…"),
      ("dock", "Toggle Terminal Dock"), ("close", "Close Terminal Sessions"),
      ("followActive", "Follow Active Pane"), ("followFirst", "Follow Left / Top Pane"),
      ("followSecond", "Follow Right / Bottom Pane"),
    ] {
      commands.append(
        AppCommand(
          id: "terminal." + id, title: title, menuPath: ["View", "Terminal"],
          isEnabled: { [weak self] context in
            context.hasBrowserWindow
              && (id.hasPrefix("follow") || self?.currentWindow?.terminal.panel.isVisible == true)
          },
          disabledReason: { _ in "Show the terminal in a browser window first." },
          isChecked: { [weak self] _ in
            guard let terminal = self?.currentWindow?.terminal else { return false }
            switch id {
            case "link": return terminal.isLinked
            case "reverseSync": return terminal.reverseSync
            case "followActive": return terminal.followMode == .active
            case "followFirst": return terminal.followMode == .first
            case "followSecond": return terminal.followMode == .second
            default: return false
            }
          },
          handler: { [weak self] in self?.currentWindow?.terminal.perform(command: id) }))
    }
    return commands
  }

  // MARK: Metadata, preview and utilities (M05)

  private var selectedLocalURLs: [URL] {
    browser.activePane.selectedEntries.filter { $0.location.providerID == provider.id }
      .map { URL(fileURLWithPath: $0.location.path) }
  }

  private func linkDisabledReason(_ kind: LocalLinkKind, otherPane: Bool) -> String? {
    let destination = otherPane ? browser.targetPane?.location : browser.activePane.location
    guard let destination, destination.providerID == provider.id else {
      return "Open a local destination pane."
    }
    let url = URL(fileURLWithPath: destination.path)
    guard FileManager.default.isWritableFile(atPath: url.path),
      let values = try? url.resourceValues(forKeys: [
        .volumeSupportsSymbolicLinksKey, .volumeSupportsPersistentIDsKey,
        .volumeSupportsExclusiveRenamingKey, .volumeIsReadOnlyKey,
      ]),
      values.volumeIsReadOnly == false
    else { return "The destination is not writable." }
    if kind == .symlink && values.volumeSupportsSymbolicLinks != true {
      return "This volume does not support symbolic links."
    }
    if kind == .alias
      && (values.volumeSupportsPersistentIDs != true
        || values.volumeSupportsExclusiveRenaming != true)
    {
      return "This volume does not support safe Finder alias creation."
    }
    if kind == .alias
      && browser.activePane.selectedEntries.contains(where: { $0.kind == .symbolicLink })
    {
      return "Use Make Symlink for symbolic link leaves."
    }
    return nil
  }

  private func makeLinks(_ kind: LocalLinkKind, otherPane: Bool) {
    let urls = selectedLocalURLs
    let sourcePane = browser.activePane
    let destination = otherPane ? browser.targetPane?.location : nil
    let model = browser
    Task {
      do {
        let service = LocalLinkService()
        for url in urls {
          let directory = destination.map { URL(fileURLWithPath: $0.path) }
          if kind == .alias {
            _ = try await service.createAlias(source: url, in: directory)
          } else {
            _ = try await service.createSymlink(source: url, in: directory)
          }
        }
      } catch { model.notice = error.localizedDescription }
      await sourcePane.refresh()
      for controller in windows { await controller.browser.refreshAll() }
    }
  }

  private func metadataUtilityCommands() -> [AppCommand] {
    func command(
      _ id: String, _ title: String, menu: [String] = ["File"], key: String? = nil,
      needsSelection: Bool = true, condition: @escaping () -> Bool = { true },
      reason: String = "Select local items in the browser first.", action: @escaping () -> Void
    ) -> AppCommand {
      AppCommand(
        id: id, title: title, menuPath: menu, shortcut: key,
        isEnabled: { [weak self] context in
          guard let self else { return false }
          return browserIsFront && !(NSApp.keyWindow?.firstResponder is NSText)
            && !context.isLoading && !fileOperations.isBusy
            && context.sourceLocation?.providerID == provider.id
            && (!needsSelection
              || (!selectedLocalURLs.isEmpty
                && selectedLocalURLs.count == context.selectionCount))
            && condition()
        }, disabledReason: { _ in reason }, handler: action)
    }
    var result = [
      command("file.getInfo", "Get Info", key: "i") { [weak self] in
        guard let self else { return }
        filePreviews.showInfo(selectedLocalURLs)
      },
      command("file.share", "Share…") { [weak self] in
        guard let self, let view = browserWindow?.contentView else { return }
        NSSharingServicePicker(items: selectedLocalURLs)
          .show(relativeTo: .zero, of: view, preferredEdge: .minY)
      },
      command("file.tags", "Tags…") { [weak self] in
        guard let self else { return }
        filePreviews.showInfo(selectedLocalURLs)
      },
      command("file.quickLook", "Quick Look", key: DefaultShortcuts.quickLook.key) { [weak self] in
        guard let self else { return }
        filePreviews.showQuickLook(selectedLocalURLs)
      },
      command(
        "file.slideshow", "Slideshow",
        condition: { [weak self] in
          self?.selectedLocalURLs.contains { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image))
              == true
          } == true
        }, reason: "Select at least one supported image.",
        action: { [weak self] in
          guard let self else { return }
          filePreviews.showSlideshow(selectedLocalURLs)
        }),
      command(
        "file.print", "Print…", key: "p",
        condition: { [weak self] in
          guard let urls = self?.selectedLocalURLs, urls.count == 1 else { return false }
          return FilePreviewCoordinator.canPrint(urls[0])
        }, reason: "Select one printable image, PDF or text file.",
        action: { [weak self] in
          guard let self, let url = selectedLocalURLs.first else { return }
          filePreviews.printFile(url)
        }),
      command(
        "commands.checksum", "Calculate Checksum…", menu: ["Commands"],
        condition: { [weak self] in
          guard let entries = self?.browser.activePane.selectedEntries else { return false }
          return entries.count == 1 && entries[0].kind == .file
        }, reason: "Select one regular local file to calculate its checksum.",
        action: { [weak self] in
          guard let self, let url = selectedLocalURLs.first else { return }
          fileUtilities.showChecksum(url)
        }),
      command(
        "commands.folderSizes", "Calculate All Folder Sizes", menu: ["Commands"],
        needsSelection: false
      ) { [weak self] in
        guard let self else { return }
        fileUtilities.calculateFolderSizes(browser.activePane)
      },
    ]
    for (format, title) in [
      (CopyPathFormat.unix, "UNIX"), (.fileURL, "URL"), (.decodedURL, "Percent-Decoded URL"),
      (.name, "Name"), (.terminal, "Terminal"), (.windows, "Windows"),
    ] {
      result.append(
        command("file.copyPath.\(format.rawValue)", title, menu: ["File", "Copy Path"]) {
          [weak self] in
          guard let self else { return }
          do {
            let text = try selectedLocalURLs.map {
              try CopyPathFormatter.string(for: $0, format: format)
            }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
          } catch { browser.notice = error.localizedDescription }
        })
    }
    for (kind, title) in [(LocalLinkKind.alias, "Alias"), (.symlink, "Symlink")] {
      for otherPane in [false, true] {
        result.append(
          command(
            "file.make\(title)\(otherPane ? "To" : "")", "Make \(title)\(otherPane ? " to" : "")",
            condition: { [weak self] in
              guard let self else { return false }
              let destination =
                otherPane ? browser.targetPane?.location : browser.activePane.location
              return destination?.providerID == provider.id
                && linkDisabledReason(kind, otherPane: otherPane) == nil
            },
            reason:
              "The destination must be a writable local volume supporting this link type; aliases cannot target symlink leaves."
          ) { [weak self] in self?.makeLinks(kind, otherPane: otherPane) })
      }
    }
    for (id, title) in [("file.copyURL", "Copy URL"), ("file.openURL", "Open URL")] {
      result.append(
        AppCommand(
          id: id, title: title, menuPath: ["File"],
          isEnabled: { [weak self] _ in self?.selectedPublicURLs().isEmpty == false },
          disabledReason: { _ in
            "Select an item on a connection that has a Base URL (Connect › Show Advanced)."
          },
          handler: { [weak self] in
            guard let urls = self?.selectedPublicURLs(), !urls.isEmpty else { return }
            if id == "file.copyURL" {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(
                urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
            } else {
              for url in urls { NSWorkspace.shared.open(url) }
            }
          }))
    }
    return result
  }

  private func selectedPublicURLs() -> [URL] {
    browser.activePane.selectedEntries.compactMap { connections.publicURL(for: $0.location) }
  }

  // MARK: Local file operations (M04)

  private func openSync(favorite: SyncFavorite? = nil) {
    guard let left = favorite?.left ?? browser.firstPane.location,
      let right = favorite?.right ?? browser.secondPane.location,
      favorite != nil || browser.canCoordinatePanes
    else { return }
    let model = SyncDialogModel(
      left: left, right: right, leftLabel: connections.describe(left),
      rightLabel: connections.describe(right), options: favorite?.options ?? SyncOptions(),
      favorite: favorite, registry: providerRegistry,
      saveFavorite: { [weak self] favorite in
        guard let self else { return }
        if let index = settings.syncFavorites.firstIndex(where: { $0.id == favorite.id }) {
          settings.syncFavorites[index] = favorite
        } else {
          settings.syncFavorites.append(favorite)
        }
        menuCoordinator?.refreshEnabling()
      },
      removeFavorite: { [weak self] id in
        self?.settings.syncFavorites.removeAll { $0.id == id }
        self?.menuCoordinator?.refreshEnabling()
      },
      submit: { [weak self] actions, left, right in
        self?.fileOperations.submitSync(actions, left: left, right: right)
      }
    )
    NotificationCenter.default.post(
      name: .fileTermSync, object: browser, userInfo: ["model": model])
  }

  private func openBatchRename(_ pane: PaneModel, preset: RenamePreset? = nil) {
    guard
      let controller = windows.first(where: { controller in
        PaneID.allCases.contains { id in
          controller.browser.tabs(id).tabs.contains { $0 === pane }
        }
      })
    else { return }
    // The order shown in the pane decides which item gets which sequence number.
    let selected = pane.entryGroups.flatMap(\.entries).filter { pane.selection.contains($0.id) }
    let items = selected.map {
      RenameItem(
        location: $0.location, name: $0.name, isDirectory: $0.kind == .directory,
        modifiedAt: $0.modifiedAt, createdAt: $0.createdAt)
    }
    let window = controller.window
    var existing: [String: Set<String>] = [:]
    if let folder = pane.location?.path { existing[folder] = Set(pane.entries.map(\.name)) }
    let model = BatchRenameModel(
      items: items, rules: preset?.rules ?? [RenameRule(kind: .replaceText)],
      existingNames: existing, presets: settings.renamePresets,
      savePreset: { [weak self] preset in
        self?.settings.renamePresets.append(preset)
        self?.menuCoordinator?.refreshEnabling()
      },
      deletePreset: { [weak self] id in self?.settings.renamePresets.removeAll { $0.id == id } },
      submit: { [weak self, weak pane] renames in
        guard let pane else { return }
        self?.fileOperations.submitBatchRename(renames, pane: pane, window: window)
      })
    NotificationCenter.default.post(
      name: .fileTermBatchRename, object: controller.browser, userInfo: ["model": model])
  }

  /// Go › Favorites: top-level favorites and groups as submenus. A connection with several saved
  /// paths gets a submenu with one entry per path.
  private func favoriteCommands() -> [AppCommand] {
    func commands(for item: FavoriteItem, in menu: [String]) -> [AppCommand] {
      func command(_ id: String, _ title: String, _ menu: [String], path: String?) -> AppCommand {
        AppCommand(
          id: id, title: title, menuPath: menu, isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open the browser window first." },
          handler: { [weak self] in
            guard let self else { return }
            let model = browser
            Task { await self.connections.openFavorite(item, path: path, in: model) }
          })
      }
      if case .connection(_, let paths) = item.target, paths.count > 1 {
        return paths.enumerated().map { index, path in
          command("go.favorites.item.\(item.id).\(index)", path, menu + [item.name], path: path)
        }
      }
      return [command("go.favorites.item.\(item.id)", item.name, menu, path: nil)]
    }
    let root = ["Go", "Favorites"]
    var result: [AppCommand] = []
    for node in settings.favorites {
      switch node {
      case .item(let item): result += commands(for: item, in: root)
      case .group(let group):
        for item in group.items { result += commands(for: item, in: root + [group.name]) }
      }
    }
    if result.isEmpty {
      result.append(
        AppCommand(
          id: "go.favorites.empty", title: "No Favorites", menuPath: root,
          isEnabled: { _ in false },
          disabledReason: { _ in "Use Go › Manage Favorites… to add one." }, handler: {}))
    }
    return result
  }

  /// Go › Workspaces: save the open windows, or load a saved set. These also reach Quick Open
  /// as commands.
  private func savedWorkspaceCommands() -> [AppCommand] {
    let root = ["Go", "Workspaces"]
    let save = AppCommand(
      id: "go.workspaces.save", title: "Save Workspace…", menuPath: root,
      isEnabled: { $0.hasBrowserWindow },
      disabledReason: { _ in "Open the browser window first." },
      handler: { [weak self] in self?.saveWorkspace() })
    return [save]
      + settings.savedWorkspaces.map { workspace in
        AppCommand(
          id: "go.workspaces.load.\(workspace.id)", title: workspace.name, menuPath: root,
          isEnabled: { _ in true }, disabledReason: { _ in "" },
          handler: { [weak self] in self?.load(workspace) })
      }
  }

  private func saveWorkspace() {
    let alert = NSAlert()
    alert.messageText = "Save Workspace"
    alert.informativeText = "Saves the open windows with their tabs, panes and locations."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.placeholderString = "Workspace name"
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if settings.savedWorkspaces.contains(where: { $0.name.lowercased() == name.lowercased() }) {
      let replace = NSAlert()
      replace.messageText = "Replace the workspace “\(name)”?"
      replace.addButton(withTitle: "Replace")
      replace.addButton(withTitle: "Cancel")
      guard replace.runModal() == .alertFirstButtonReturn else { return }
    }
    settings.saveWorkspace(named: name, windows: windows.map { $0.snapshot() })
  }

  /// Opens the workspace's windows, then closes the ones that were open.
  private func load(_ workspace: SavedWorkspace) {
    guard FilePreviewContentView.confirmTermination() else { return }
    let current = windows
    if current.contains(where: \.terminal.hasSessions) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Load the workspace “\(workspace.name)”?"
      alert.informativeText = "This closes the open windows and ends their terminal sessions."
      alert.addButton(withTitle: "Load")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    Task {
      for snapshot in workspace.windows { await newWindow(restoring: snapshot) }
      for controller in current { controller.window.close() }
    }
  }

  /// Commands › Tools: one entry per user tool, available by the tool's own rules.
  private func toolCommands() -> [AppCommand] {
    settings.tools.map { tool in
      AppCommand(
        id: "tools.run.\(tool.id)", title: tool.name, menuPath: ["Commands", "Tools"],
        isEnabled: { [weak self] context in
          guard let self else { return false }
          return browserIsFront && context.hasBrowserWindow && !context.isLoading
            && toolDisabledReason(tool) == nil
        },
        disabledReason: { [weak self] context in
          guard let self else { return "" }
          if !context.hasBrowserWindow { return "Open the browser window first." }
          if context.isLoading { return "Wait for navigation to finish." }
          return toolDisabledReason(tool) ?? ""
        },
        handler: { [weak self] in
          guard let self, let source = browser.activePane.location else { return }
          let pane = browser.activePane
          let target = browser.targetPane
          toolRunner.run(
            tool,
            context: ToolCommandBuilder.Context(
              sourcePath: source.path, targetPath: target?.location?.path,
              sourceSelection: pane.selectedEntries.map(\.location.path),
              targetSelection: target?.selectedEntries.map(\.location.path) ?? []),
            source: source)
        })
    }
  }

  /// Edit needs exactly one regular file, local or on a connection.
  private func editDisabledReason() -> String? {
    let entries = browser.activePane.selectedEntries
    guard entries.count == 1, let entry = entries.first, entry.kind == .file else {
      return "Select one file to edit."
    }
    return entry.location.providerID.hasPrefix("archive:")
      ? "Files inside an archive cannot be edited." : nil
  }

  private func gitDisabledReason(needsSelection: Bool) -> String? {
    guard let location = browser.activePane.location, location.providerID == "local" else {
      return "Source control works in local folders only."
    }
    guard GitRepository.root(from: location.path) != nil else {
      return "The current folder is not in a Git repository."
    }
    if needsSelection, browser.activePane.selection.isEmpty { return "Select the items to add." }
    return nil
  }

  private func toolDisabledReason(_ tool: UserTool) -> String? {
    let pane = browser.activePane
    return ToolRunner.disabledReason(
      for: tool, source: pane.location, target: browser.targetPane?.location,
      selectionCount: pane.selection.count)
      ?? tool.requiredProgram.flatMap { Prerequisites.live.missing(.commandLineProgram($0)) }
  }

  /// The selected local items in the given iCloud state.
  private func selectedPaths(in state: ICloudFileState) -> [String] {
    browser.activePane.selectedEntries.map(\.location.path).filter {
      ICloudFiles.state(of: URL(fileURLWithPath: $0)) == state
    }
  }

  private var selectedDropboxPath: String? {
    let entries = browser.activePane.selectedEntries
    return entries.count == 1 ? entries[0].location.path : nil
  }

  private func syncFavoriteCommands() -> [AppCommand] {
    settings.syncFavorites.map { favorite in
      AppCommand(
        id: "commands.syncFavorite.\(favorite.id)", title: favorite.name,
        menuPath: ["Commands", "Sync Favorites"], isEnabled: { $0.hasBrowserWindow },
        disabledReason: { _ in "Open the browser window first." },
        handler: { [weak self] in self?.runSyncFavorite(favorite) })
    }
  }

  /// Shows both folders side by side, then always opens the analysis preview; it never syncs.
  private func runSyncFavorite(_ favorite: SyncFavorite) {
    let model = browser
    guard
      [favorite.left, favorite.right].allSatisfy({
        providerRegistry.provider(for: $0.providerID) != nil
      })
    else {
      model.notice = "Connect to the locations of “\(favorite.name)” first, then run it again."
      return
    }
    if model.layout == .single { model.setLayout(model.lastDualLayout) }
    Task {
      let first = await model.navigate(to: favorite.left, in: .first)
      let second = await model.navigate(to: favorite.right, in: .second)
      guard first, second else {
        model.notice = "“\(favorite.name)” could not open both folders."
        return
      }
      openSync(favorite: favorite)
    }
  }

  private func fileOperationCommands() -> [AppCommand] {
    func command(
      _ id: String, _ title: String, menu: [String] = ["Commands"],
      shortcut: Shortcut? = nil, selection: Bool = false, target: Bool = false,
      anyProvider: Bool = false,
      condition: @escaping () -> Bool = { true },
      reason: @escaping () -> String = {
        "Open a local folder and select the required items. Pane transfers need two panes. "
          + "Remote locations support Copy to…, Move to…, Rename, Delete, New Folder and Open."
      },
      action: @escaping () -> Void
    ) -> AppCommand {
      AppCommand(
        id: id, title: title, menuPath: menu, shortcut: shortcut?.key,
        shortcutModifiers: shortcut?.modifiers ?? [.command],
        isEnabled: { [weak self] context in
          guard let self else { return false }
          return browserIsFront && !(NSApp.keyWindow?.firstResponder is NSText)
            && !context.isLoading
            && (anyProvider
              ? context.sourceLocation != nil : context.sourceLocation?.providerID == "local")
            && (!selection || context.selectionCount > 0)
            && (!target
              || (anyProvider
                ? context.targetLocation != nil : context.targetLocation?.providerID == "local"))
            && condition()
        }, disabledReason: { _ in reason() }, handler: action)
    }
    var result: [AppCommand] = []
    for (id, title, shortcut, directory, selected) in [
      ("file.newFolder", "New Folder", DefaultShortcuts.newFolder, true, false),
      (
        "file.newFolderWithSelection", "New Folder With Selection",
        DefaultShortcuts.newFolderWithSelection, true, true
      ),
      ("file.newFile", "New File", DefaultShortcuts.newFile, false, false),
    ] {
      result.append(
        command(
          id, title, menu: ["File"], shortcut: shortcut, selection: selected,
          anyProvider: id == "file.newFolder"
        ) { [weak self] in
          guard let self else { return }
          fileOperations.create(
            browser.activePane, directory: directory, withSelection: selected, window: browserWindow
          )
        })
    }
    result.append(
      command(
        "file.open", "Open", menu: ["File"], shortcut: DefaultShortcuts.open, selection: true,
        anyProvider: true
      ) { [weak self] in
        guard let self else { return }
        fileOperations.open(browser)
      })
    result.append(
      command("file.openWith.other", "Other…", menu: ["File", "Open With"], selection: true) {
        [weak self] in
        guard let self else { return }
        fileOperations.chooseApplication(browser, window: browserWindow)
      })
    for (id, git) in [
      ("add", GitCommand.add([])), ("addAll", .addAll), ("commit", .commit(message: "")),
      ("push", .push), ("pull", .pull),
    ] {
      let needsSelection = id == "add"
      result.append(
        command(
          "commands.git.\(id)", git.title + (id == "commit" ? "…" : ""),
          menu: ["Commands", "Source Control"],
          condition: { [weak self] in self?.gitDisabledReason(needsSelection: needsSelection) == nil
          },
          reason: { [weak self] in self?.gitDisabledReason(needsSelection: needsSelection) ?? "" }
        ) { [weak self] in
          guard let self, let location = browser.activePane.location,
            let root = GitRepository.root(from: location.path)
          else { return }
          switch id {
          case "add":
            let paths = browser.activePane.selectedEntries.map(\.location.path)
            gitRunner.run(.add(paths), root: root)
          case "commit":
            if let message = GitRunner.askForCommitMessage() {
              gitRunner.run(.commit(message: message), root: root)
            }
          default: gitRunner.run(git, root: root)
          }
        })
    }
    result.append(
      command(
        "file.iCloud.download", "Download Now", menu: ["File", "iCloud"], selection: true,
        condition: { [weak self] in self?.selectedPaths(in: .cloudOnly).isEmpty == false },
        reason: { "Select iCloud Drive items that are not downloaded." }
      ) { [weak self] in
        guard let self else { return }
        cloudFiles.downloadNow(selectedPaths(in: .cloudOnly))
      })
    result.append(
      command(
        "file.iCloud.removeDownload", "Remove Download", menu: ["File", "iCloud"], selection: true,
        condition: { [weak self] in self?.selectedPaths(in: .downloaded).isEmpty == false },
        reason: { "Select downloaded iCloud Drive items. The files stay in iCloud." }
      ) { [weak self] in
        guard let self else { return }
        cloudFiles.removeDownload(selectedPaths(in: .downloaded))
      })
    result.append(
      command(
        "file.copyDropboxLink", "Copy Dropbox Link", menu: ["File"], selection: true,
        condition: { [weak self] in
          guard let self, let path = selectedDropboxPath,
            case .ready = cloudFiles.dropboxLinkState(path)
          else { return false }
          return true
        },
        reason: { [weak self] in
          guard let self, let path = selectedDropboxPath else {
            return "Select one item in a Dropbox folder."
          }
          if case .unavailable(let reason) = cloudFiles.dropboxLinkState(path) { return reason }
          return "Select one item in a Dropbox folder."
        }
      ) { [weak self] in
        guard let self, let path = selectedDropboxPath else { return }
        Task { await self.cloudFiles.copyDropboxLink(path) }
      })
    result.append(
      command(
        "file.openInTerminal", "Open in Terminal", menu: ["File"],
        condition: { [weak self] in self?.settings.terminalApplication.isInstalled == true },
        reason: { [weak self] in
          guard let self, browser.activePane.location?.providerID == "local" else {
            return "Only local folders can be opened in a terminal."
          }
          return
            "\(settings.terminalApplication.title) is not installed. Choose another in Settings › General › Terminal Application."
        }
      ) { [weak self] in
        guard let self, let folder = browser.activePane.location,
          let path = settings.terminalApplication.applicationPath()
        else { return }
        let model = browser
        let name = settings.terminalApplication.title
        NSWorkspace.shared.open(
          [URL(fileURLWithPath: folder.path, isDirectory: true)],
          withApplicationAt: URL(fileURLWithPath: path),
          configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
          guard let error else { return }
          Task { @MainActor in
            model.notice = "Could not open \(name): \(error.localizedDescription)"
          }
        }
      })
    result.append(
      command(
        "commands.edit", "Edit", selection: true, anyProvider: true,
        condition: { [weak self] in
          guard let self else { return false }
          return editDisabledReason() == nil
        },
        reason: { [weak self] in self?.editDisabledReason() ?? "" }
      ) { [weak self] in
        guard let self, let entry = browser.activePane.selectedEntries.first else { return }
        let model = browser
        let editors = settings.editors
        guard entry.location.providerID == "local" else {
          remoteEdits.edit(entry, editors: editors) { model.notice = $0 }
          return
        }
        let url = URL(fileURLWithPath: entry.location.path)
        Task { @MainActor in
          if let message = await self.fileOperations.openInEditor(url, editors: editors) {
            model.notice = message
          }
        }
      })
    result.append(
      command(
        "file.packageContents", "Show Package Contents", menu: ["File"], selection: true,
        condition: { [weak self] in
          self?.browser.activePane.selectedEntries.contains {
            (try? URL(fileURLWithPath: $0.location.path).resourceValues(forKeys: [.isPackageKey])
              .isPackage) == true
          } == true
        }
      ) { [weak self] in
        guard let self else { return }
        fileOperations.open(browser, packageContents: true)
      })
    for (id, title, move, renamed) in [
      ("commands.copyTo", "Copy to…", false, false),
      ("commands.copyToAs", "Copy to as…", false, true),
      ("commands.moveTo", "Move to…", true, false),
    ] {
      result.append(
        command(
          id, title, selection: true, target: true, anyProvider: true,
          condition: { [weak self] in !renamed || self?.browser.activePane.selection.count == 1 }
        ) { [weak self] in
          guard let self else { return }
          fileOperations.transfer(browser, move: move, asNewName: renamed, window: browserWindow)
        })
    }
    result.append(
      command(
        "edit.moveItemsHere", "Move Items Here", menu: ["Edit"],
        shortcut: Shortcut(key: "v", modifiers: [.command, .option]), anyProvider: true,
        condition: { [weak self] in self?.fileOperations.clipboardURLs.isEmpty == false }
      ) { [weak self] in
        guard let self else { return }
        fileOperations.transfer(browser, move: true, clipboard: true, window: browserWindow)
      })
    result.append(
      command(
        "commands.duplicate", "Duplicate", shortcut: Shortcut(key: "d", command: true),
        selection: true
      ) { [weak self] in
        guard let self else { return }
        fileOperations.duplicate(browser.activePane, window: browserWindow)
      })
    result.append(
      command("commands.rename", "Rename", selection: true, anyProvider: true) { [weak self] in
        guard let self else { return }
        fileOperations.startRename(browser.activePane, window: browserWindow)
      })
    let archiveReason: () -> String = { [weak self] in
      self?.settings.handleArchives == false
        ? "Turn on Settings › General › Handle archives with FileTerm."
        : "Select an archive (.zip, .tar, .tar.gz, .7z…) in a local folder."
    }
    let compressReason: () -> String = { [weak self] in
      self?.settings.handleArchives == false
        ? "Turn on Settings › General › Handle archives with FileTerm."
        : "Select one or more items in a local folder."
    }
    for (id, title, options) in [
      ("commands.compress", "Compress", false),
      ("commands.compressOptions", "Compress With Options…", true),
    ] {
      result.append(
        command(
          id, title, selection: true,
          condition: { [weak self] in self?.settings.handleArchives == true },
          reason: compressReason
        ) { [weak self] in
          guard let self else { return }
          fileOperations.compress(browser, withOptions: options, window: browserWindow)
        })
    }
    for (id, title, choose) in [
      ("commands.extract", "Extract", false),
      ("commands.extractTo", "Extract to…", true),
    ] {
      result.append(
        command(
          id, title, selection: true,
          condition: { [weak self] in
            guard let self, settings.handleArchives else { return false }
            let entries = browser.activePane.selectedEntries
            return !entries.isEmpty && entries.allSatisfy(fileOperations.isArchive)
          }, reason: archiveReason
        ) { [weak self] in
          guard let self else { return }
          fileOperations.extract(browser, choose: choose, window: browserWindow)
        })
    }
    result.append(
      command(
        "file.trash", "Move to Trash",
        shortcut: Shortcut(key: "\u{7F}", command: true), selection: true, anyProvider: true
      ) { [weak self] in
        guard let self else { return }
        fileOperations.trash(browser.activePane, window: browserWindow)
      })
    let compareSelection: () -> CompareSelection = { [weak self] in
      guard let self else { return .unavailable("") }
      return CompareSelection.resolve(
        active: browser.activePane.selectedEntries,
        other: browser.targetPane?.selectedEntries ?? [])
    }
    result.append(
      command(
        "commands.compare", "Compare", selection: true, anyProvider: true,
        condition: { [weak self] in
          guard let self, settings.compareTool.isInstalled,
            case .pair = compareSelection()
          else { return false }
          return true
        },
        reason: { [weak self] in
          guard let self else { return "" }
          if let missing = Prerequisites.live.missing(.compareTool(settings.compareTool)) {
            return missing
          }
          if case .unavailable(let reason) = compareSelection() { return reason }
          return ""
        }
      ) { [weak self] in
        guard let self, case .pair(let left, let right) = compareSelection() else { return }
        do { try settings.compareTool.launch(left: left, right: right) } catch {
          let alert = NSAlert()
          alert.messageText = "Could not open \(settings.compareTool.title)"
          alert.informativeText = error.localizedDescription
          alert.runModal()
        }
      })
    result.append(
      command(
        "commands.appCleanup", "Delete App and Related Files…", selection: true,
        condition: { [weak self] in
          self?.browser.activePane.selectedEntries.count == 1
            && self?.browser.activePane.selectedEntries.first.map {
              FileOperationCoordinator.isApplication(URL(fileURLWithPath: $0.location.path))
            } == true
        },
        reason: { "Select an application (.app) in a local folder to find its related files." }
      ) { [weak self] in
        guard let self else { return }
        fileOperations.trash(browser.activePane, window: browserWindow, appCleanup: true)
      })
    result.append(
      command(
        "commands.delete", "Delete…",
        shortcut: Shortcut(key: "\u{7F}", command: true, option: true), selection: true,
        anyProvider: true
      ) { [weak self] in
        guard let self else { return }
        fileOperations.deletePermanently(browser.activePane, window: browserWindow)
      })
    for redo in [false, true] {
      result.append(
        AppCommand(
          id: redo ? "edit.redo" : "edit.undo", title: redo ? "Redo" : "Undo", menuPath: ["Edit"],
          shortcut: "z",
          shortcutModifiers: redo ? [.command, .shift] : [.command],
          isEnabled: { [weak self] _ in
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
              return redo ? text.undoManager?.canRedo == true : text.undoManager?.canUndo == true
            }
            guard let self else { return false }
            return browserIsFront && !fileOperations.isBusy
              && (redo ? fileOperations.canRedo : fileOperations.canUndo)
          },
          disabledReason: { [weak self] _ in
            guard let self else { return "No history available." }
            if fileOperations.isBusy { return "Another file operation is in progress." }
            return redo ? fileOperations.redoReason : fileOperations.undoReason
          },
          handler: { [weak self] in
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
              if redo { text.undoManager?.redo() } else { text.undoManager?.undo() }
            } else if let self {
              fileOperations.history(redo: redo, pane: browser.activePane, window: browserWindow)
            }
          }))
    }
    return result
  }

  private func openWithCommands() -> [AppCommand] {
    let entries = browser.activePane.selectedEntries
    guard let first = entries.first else { return [] }
    var applications = Set(
      NSWorkspace.shared.urlsForApplications(toOpen: URL(fileURLWithPath: first.location.path)))
    for entry in entries.dropFirst() {
      applications.formIntersection(
        NSWorkspace.shared.urlsForApplications(toOpen: URL(fileURLWithPath: entry.location.path)))
    }
    return applications.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { application in
      AppCommand(
        id: "file.openWith." + application.path,
        title: application.deletingPathExtension().lastPathComponent,
        menuPath: ["File", "Open With"],
        isEnabled: { [weak self] _ in self?.browserIsFront == true },
        disabledReason: { _ in "Select an item in the browser." },
        handler: { [weak self] in
          guard let self else { return }
          fileOperations.open(browser, application: application)
        })
    }
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
    return [
      AppCommand(
        id: "edit.selectAll", title: "Select All", menuPath: ["Edit"], shortcut: "a",
        isEnabled: { context in
          NSApp.keyWindow?.firstResponder is NSText
            || NSApp.keyWindow?.firstResponder is TerminalView || inBrowser(context)
        },
        disabledReason: noWindow,
        handler: { [weak self] in
          guard let self else { return }
          if !browser.isQuickOpenOpen,
            let first = NSApp.keyWindow?.firstResponder,
            first is NSText || first is TerminalView
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
        disabledReason: {
          $0.hasBrowserWindow ? "Nothing is selected." : "Open the browser window first."
        },
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
            ? "Close the search first."
            : "Quick Open is unavailable while editing text or in a dialog."
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
