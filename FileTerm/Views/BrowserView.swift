import AppKit
import FileTermCore
import SwiftUI
import UniformTypeIdentifiers

/// A divider that resizes the panel beside it. `direction` is 1 when dragging right widens it.
private struct PanelResizeHandle: View {
  @Binding var width: CGFloat
  let shownWidth: CGFloat
  let range: ClosedRange<CGFloat>
  let direction: CGFloat
  @State private var startWidth: CGFloat?

  var body: some View {
    Divider()
      .overlay {
        Color.clear.frame(width: 9).contentShape(Rectangle())
          .onHover { isHovering in
            if isHovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
          }
          .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
              .onChanged { value in
                let start = startWidth ?? shownWidth
                startWidth = start
                let proposed = start + direction * value.translation.width
                width = min(max(proposed, range.lowerBound), range.upperBound)
              }
              .onEnded { _ in startWidth = nil }
          )
      }
      .accessibilityElement()
      .accessibilityLabel("Resize panel")
  }
}

struct BrowserView: View {
  @Bindable var browser: BrowserModel
  let settings: AppSettings
  let registry: CommandRegistry
  let localProvider: LocalFileSystemProvider
  let devices: DeviceModel
  @Bindable var terminal: TerminalWorkspace
  let transfers: TransferQueue
  let connections: ConnectionCoordinator
  @State private var connectionForm: ConnectionFormModel?
  @State private var goToFolder: GoToFolderModel?
  @State private var optionsSheet: BrowserOptionsSheet?
  @State private var quickSelectShown = false
  @State private var syncModel: SyncDialogModel?
  @State private var batchRename: BatchRenameModel?
  @State private var quickOpenShown = false
  @State private var pendingQuickOpen: QuickOpenItem?
  @State private var extensionPoints = QuickOpenExtensionPoints()
  @State private var favoriteManagerRequest: FavoriteManagerRequest?
  @State private var favoriteToDelete: FavoriteItem?
  @State private var favoriteDropTargeted = false
  @State private var sidebarWidth: CGFloat = 170
  @State private var previewWidth: CGFloat = 320

  var body: some View {
    VStack(spacing: 0) {
      if let notice = browser.notice {
        HStack {
          Label(notice, systemImage: "info.circle").font(.callout)
          Spacer()
          Button("Dismiss") { browser.dismissNotice() }
        }
        .padding(8).accessibilityIdentifier("browserNotice")
        Divider()
      }
      terminalLayout
      if settings.isVisible(.activities) || settings.isVisible(.logs) {
        Divider()
        HSplitView {
          if settings.isVisible(.activities) { TransferActivitiesPanel(queue: transfers) }
          if settings.isVisible(.logs) { TransferLogsPanel(queue: transfers) }
        }.frame(height: 200)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .modifier(ThemedBrowser(theme: settings.theme))
    .frame(minWidth: 680, minHeight: 420)
    .onChange(of: settings.transfers, initial: true) { _, value in
      transfers.preferences = value
    }
    .onAppear {
      extensionPoints.favorites = [
        ClosureQuickOpenSource { [settings, browser, connections] in
          settings.favorites.allItems.map { item in
            QuickOpenItem(id: "favorite:\(item.id)", title: item.name, kind: .favorite) {
              Task { await connections.openFavorite(item, in: browser) }
            }
          }
        }
      ]
      extensionPoints.renamePresets = [
        ClosureQuickOpenSource { [settings, browser] in
          settings.renamePresets.map { preset in
            let pane = browser.activePane
            return QuickOpenItem(
              id: "renamePreset:\(preset.id)", title: preset.name,
              subtitle: pane.selection.count > 1
                ? "Rename preset" : "Rename preset — select several items first",
              kind: .renamePreset, isEnabled: pane.selection.count > 1,
              perform: {
                NotificationCenter.default.post(
                  name: .fileTermRenamePreset, object: pane, userInfo: ["presetID": preset.id])
              })
          }
        }
      ]
    }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermGoToFolder)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      goToFolder = GoToFolderModel(
        browser: browser, provider: localProvider, paneID: browser.activePaneID,
        settings: settings)
    }
    .sheet(item: $goToFolder) { model in GoToFolderSheet(model: model) }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermConnect)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      let saved = (notification.userInfo?["profileID"] as? UUID).flatMap { id in
        connections.profiles.first { $0.id == id }
      }
      connectionForm = ConnectionFormModel(
        profile: saved ?? ConnectionProfile(kind: .smb), isEditing: saved != nil,
        coordinator: connections, browser: browser)
    }
    .sheet(item: $connectionForm) { model in ConnectionFormSheet(model: model) }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermQuickSelect)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      quickSelectShown = true
    }
    .sheet(isPresented: $quickSelectShown) { QuickSelectSheet(pane: browser.activePane) }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermSync)) { notification in
      guard notification.object as? BrowserModel === browser,
        let model = notification.userInfo?["model"] as? SyncDialogModel
      else { return }
      syncModel = model
    }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermBatchRename)) { notification in
      guard notification.object as? BrowserModel === browser,
        let model = notification.userInfo?["model"] as? BatchRenameModel
      else { return }
      batchRename = model
    }
    .sheet(item: $batchRename) { model in BatchRenameSheet(model: model) }
    .sheet(item: $syncModel, onDismiss: { syncModel?.cancel() }) { model in SyncSheet(model: model)
    }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermQuickOpen)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      browser.isQuickOpenOpen = true
      quickOpenShown = true
    }
    .sheet(
      isPresented: $quickOpenShown,
      onDismiss: {
        browser.isQuickOpenOpen = false
      }
    ) {
      QuickOpenSheet(sources: quickOpenSources) { item in
        quickOpenShown = false
        browser.isQuickOpenOpen = false
        if item.id == "command:edit.selectAll" {
          browser.activePane.selectAll()
        } else {
          item.perform()
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermBrowserOptions)) { notification in
      guard notification.object as? BrowserModel === browser,
        let kind = notification.userInfo?["kind"] as? String
      else { return }
      optionsSheet = BrowserOptionsSheet(rawValue: kind)
    }
    .sheet(item: $favoriteManagerRequest) { request in
      FavoritesManagerSheet(
        settings: settings, connections: connections, browser: browser,
        reveal: request.favorite, editsRevealed: request.edits)
    }
    .sheet(item: $optionsSheet) { sheet in
      switch sheet {
      case .viewOptions: ViewOptionsSheet(pane: browser.activePane)
      case .sidebar: SidebarEditorSheet(settings: settings)
      case .favorites:
        FavoritesManagerSheet(settings: settings, connections: connections, browser: browser)
      case .favoritesImport: FavoritesImportSheet(settings: settings)
      }
    }
    .alert(
      "Device",
      isPresented: Binding(
        get: { devices.errorMessage != nil }, set: { if !$0 { devices.errorMessage = nil } })
    ) {
      Button("OK") { devices.errorMessage = nil }
    } message: {
      Text(devices.errorMessage ?? "")
    }
  }

  @ViewBuilder private var terminalLayout: some View {
    if terminal.panel.isVisible {
      if terminal.panel.dock == .right {
        HSplitView {
          browserContent
          terminalDrawer.frame(minWidth: 260, idealWidth: terminal.panel.size)
        }
      } else {
        VSplitView {
          browserContent
          terminalDrawer.frame(minHeight: 120, idealHeight: terminal.panel.size)
        }
      }
    } else {
      browserContent
    }
  }

  private var terminalDrawer: some View {
    TerminalPanel(workspace: terminal)
  }

  /// The sidebar and preview keep their width when the window resizes, so the panes take the
  /// change. An `HSplitView` would give them spare width up to their maximum instead.
  private var browserContent: some View {
    let hasSidebar = settings.isVisible(.sidebar)
    let hasPreview = settings.isVisible(.preview)
    let panesMinimum: CGFloat = browser.layout == .vertical ? 440 : 220
    let sidebarMinimum: CGFloat = 120
    let previewMinimum: CGFloat = 300
    return GeometryReader { geometry in
      let available = geometry.size.width - panesMinimum
      let sidebarRange =
        sidebarMinimum...max(sidebarMinimum, available - (hasPreview ? previewMinimum : 0))
      let shownSidebar = min(sidebarWidth, sidebarRange.upperBound)
      let previewRange =
        previewMinimum...max(previewMinimum, available - (hasSidebar ? shownSidebar : 0))
      HStack(spacing: 0) {
        if hasSidebar {
          sidebar.frame(width: shownSidebar)
          PanelResizeHandle(
            width: $sidebarWidth, shownWidth: shownSidebar, range: sidebarRange, direction: 1
          )
          .accessibilityIdentifier("sidebarResizeHandle")
        }
        paneLayout.frame(maxWidth: .infinity)
        if hasPreview {
          PanelResizeHandle(
            width: $previewWidth, shownWidth: min(previewWidth, previewRange.upperBound),
            range: previewRange, direction: -1
          )
          .accessibilityIdentifier("previewResizeHandle")
          previewPanel.frame(width: min(previewWidth, previewRange.upperBound))
        }
      }
    }
    .frame(
      minWidth: panesMinimum + (hasSidebar ? sidebarMinimum : 0)
        + (hasPreview ? previewMinimum : 0))
  }

  @ViewBuilder private var paneLayout: some View {
    switch browser.layout {
    case .single: pane(browser.activePaneID)
    case .vertical:
      HSplitView {
        pane(.first)
        pane(.second)
      }
    case .horizontal:
      VSplitView {
        pane(.first)
        pane(.second)
      }
    }
  }

  private func pane(_ id: PaneID) -> some View {
    BrowserPaneView(
      pane: browser.pane(id), paneID: id, browser: browser,
      settings: settings, registry: registry, localProvider: localProvider,
      volumeService: devices.service
    )
    .frame(minWidth: 220, minHeight: 130)
  }

  private var quickOpenSources: [any QuickOpenSource] {
    let registry = registry
    let browser = browser
    let settings = settings
    let provider = localProvider
    let commands = ClosureQuickOpenSource {
      registry.commands.filter {
        !$0.id.hasPrefix("go.recent") && !$0.id.hasPrefix("go.connections")
          && ($0.id == "go.favorites.manage" || !$0.id.hasPrefix("go.favorites."))
          && $0.id != "quickOpen"
      }
      .map { command in
        let shortcut = registry.effectiveShortcut(for: command.id)?.display
        let reason = registry.disabledReason(for: command.id)
        return QuickOpenItem(
          id: "command:" + command.id, title: registry.title(of: command),
          subtitle: [command.menuPath.joined(separator: " › "), shortcut, reason]
            .compactMap { $0 }.joined(separator: " · "),
          kind: .command, isEnabled: reason == nil
        ) { registry.execute(command.id) }
      }
    }
    let recents = ClosureQuickOpenSource {
      settings.recentFolders.map { path in
        QuickOpenItem(
          id: "recent:" + path,
          title: URL(fileURLWithPath: path).lastPathComponent.isEmpty
            ? "/" : URL(fileURLWithPath: path).lastPathComponent,
          subtitle: path, kind: .recent
        ) {
          let id = browser.activePaneID
          Task { await browser.navigate(to: Location(providerID: provider.id, path: path), in: id) }
        }
      }
    }
    let folders = ClosureQuickOpenSource {
      browser.activePane.entries.filter { $0.kind == .directory }.map { entry in
        QuickOpenItem(
          id: "folder:" + entry.location.path, title: entry.name, subtitle: entry.location.path,
          kind: .folder
        ) {
          let id = browser.activePaneID
          Task { await browser.enterFolder(entry.location, in: id) }
        }
      }
    }
    return [commands, folders, recents] + extensionPoints.all
  }

  private var sidebar: some View {
    List {
      ForEach(settings.workspace.sidebarSections, id: \.self) { section in
        if section == "devices" && settings.isVisible(.devices) {
          Section {
            if isExpanded("devices") {
              ForEach(
                devices.volumes.filter {
                  !settings.hiddenSidebarItems.contains(SidebarItemKey.volume($0))
                }
              ) { volume in
                Button {
                  devices.selectedVolumeID = volume.id
                  open(localProvider.location(for: volume.url))
                } label: {
                  HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: volume.url.path)).resizable()
                      .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(volume.name).lineLimit(1)
                      if settings.isVisible(.deviceInfo) {
                        Text(volumeInfo(volume)).font(.caption2).foregroundStyle(.secondary)
                      }
                    }
                    Spacer(minLength: 0)
                    volumeBadge(volume)
                  }.padding(.vertical, 3).contentShape(Rectangle())
                    .background(
                      devices.selectedVolumeID == volume.id
                        ? Color.accentColor.opacity(0.15) : .clear
                    )
                }.buttonStyle(.plain).help(volume.url.path)
                  .contextMenu { volumeMenu(volume) }
              }
            }
          } header: {
            sectionHeader("Devices", section: "devices", chrome: .devices)
          }
        }
        if section == "recents" && settings.isVisible(.recentFolders) {
          Section {
            if isExpanded("recents") {
              ForEach(settings.recentFolders, id: \.self) { path in
                Button {
                  devices.selectedVolumeID = nil
                  open(Location(providerID: localProvider.id, path: path))
                } label: {
                  Label(
                    URL(fileURLWithPath: path).lastPathComponent.isEmpty
                      ? "/" : URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder"
                  ).lineLimit(1)
                }.buttonStyle(.plain).help(path)
              }
            }
          } header: {
            sectionHeader("Recent Folders", section: "recents", chrome: .recentFolders)
          }
        }
        if section == "tags" && settings.isVisible(.tags) {
          Section {
            if isExpanded("tags") {
              ForEach(settings.tags) { tag in
                Button {
                  showFiles(tagged: tag)
                } label: {
                  Label {
                    Text(tag.name).lineLimit(1)
                  } icon: {
                    Circle().fill(tag.color.swatch).frame(width: 10, height: 10)
                  }
                }.buttonStyle(.plain).accessibilityIdentifier("sidebarTag.\(tag.name)")
              }
            }
          } header: {
            sectionHeader("Tags", section: "tags", chrome: .tags)
          }
        }
        if section == "iCloudDrive" && settings.isVisible(.iCloudDrive)
          && FileManager.default.fileExists(atPath: FavoriteItem.iCloudDrivePath)
        {
          Section {
            if isExpanded("iCloudDrive") {
              Button {
                devices.selectedVolumeID = nil
                open(Location(providerID: localProvider.id, path: FavoriteItem.iCloudDrivePath))
              } label: {
                Label("iCloud Drive", systemImage: "icloud").lineLimit(1)
              }.buttonStyle(.plain).help(FavoriteItem.iCloudDrivePath)
                .accessibilityIdentifier("sidebarICloudDrive")
            }
          } header: {
            sectionHeader("iCloud", section: "iCloudDrive", chrome: .iCloudDrive)
          }
        }
        if section == "workspaces" && settings.isVisible(.workspaces)
          && !settings.savedWorkspaces.isEmpty
        {
          Section {
            if isExpanded("workspaces") {
              ForEach(settings.savedWorkspaces) { workspace in
                Button {
                  _ = registry.execute("go.workspaces.load.\(workspace.id)")
                } label: {
                  Label(workspace.name, systemImage: "rectangle.3.group").lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Load this workspace")
                .contextMenu {
                  Button("Delete Workspace") {
                    settings.savedWorkspaces.removeAll { $0.id == workspace.id }
                  }
                }
                .accessibilityIdentifier("workspace.\(workspace.name)")
              }
            }
          } header: {
            sectionHeader("Workspaces", section: "workspaces", chrome: .workspaces)
          }
        }
        if section == "favorites" && settings.isVisible(.favorites) {
          Section {
            if isExpanded("favorites") {
              if visibleFavorites(settings.favorites.allItems).isEmpty {
                Label("Drop folders here", systemImage: "star").foregroundStyle(.secondary)
                  .lineLimit(1).accessibilityIdentifier("favoritesDropHint")
              }
              ForEach(settings.favorites) { node in
                switch node {
                case .item(let item):
                  if !visibleFavorites([item]).isEmpty { favoriteRow(item) }
                case .group(let group):
                  if !visibleFavorites(group.items).isEmpty {
                    DisclosureGroup(group.name) {
                      ForEach(visibleFavorites(group.items)) { favoriteRow($0) }
                    }
                  }
                }
              }
            }
          } header: {
            sectionHeader("Favorites", section: "favorites", chrome: .favorites) {
              Button("Reveal in Favorite Manager") { revealFavorite(nil) }
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .background(Color(themeHex: settings.theme.sidebar) ?? .clear)
    .onDrop(
      of: [.fileURL, .fileTermRemoteItem],
      isTargeted: $favoriteDropTargeted,
      perform: addFavorites(from:)
    )
    .overlay {
      if favoriteDropTargeted && settings.isVisible(.favorites) {
        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
      }
    }
    .accessibilityIdentifier("navigationSidebar")
    .confirmationDialog(
      "Delete “\(favoriteToDelete?.name ?? "")” from Favorites?",
      isPresented: Binding(
        get: { favoriteToDelete != nil }, set: { if !$0 { favoriteToDelete = nil } })
    ) {
      Button("Delete", role: .destructive) {
        if let item = favoriteToDelete {
          settings.favorites = settings.favorites.removing(item.id)
        }
      }
      .accessibilityIdentifier("confirmDeleteFavorite")
    }
  }

  private func isExpanded(_ section: String) -> Bool {
    !settings.collapsedSidebarSections.contains(section)
  }

  /// Adds dragged folders to Favorites. Files, and folders that can't reopen, add nothing.
  private func addFavorites(from providers: [NSItemProvider]) -> Bool {
    guard settings.isVisible(.favorites) else { return false }
    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.fileTermRemoteItem.identifier) {
        _ = provider.loadDataRepresentation(
          forTypeIdentifier: UTType.fileTermRemoteItem.identifier
        ) { data, _ in
          guard let data, let drag = try? JSONDecoder().decode(RemoteItemDrag.self, from: data),
            drag.isDirectory
          else { return }
          Task { @MainActor in addFavorite(forFolder: drag.location) }
        }
      } else {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url, url.isFileURL,
            (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?
              .isDirectory == true
          else { return }
          let location = Location(providerID: "local", path: url.standardizedFileURL.path)
          Task { @MainActor in addFavorite(forFolder: location) }
        }
      }
    }
    return true
  }

  private func addFavorite(forFolder location: Location) {
    switch connections.favoriteDrop(forFolder: location) {
    case .add(let item): settings.favorites = settings.favorites.adding(item)
    case .refuse(let message): browser.notice = message
    case .ignore: break
    }
  }

  private func sectionHeader(
    _ title: LocalizedStringKey, section: String, chrome: BrowserChrome,
    @ViewBuilder extra: () -> some View = { EmptyView() }
  ) -> some View {
    let extra = extra()
    return Button {
      if isExpanded(section) {
        settings.collapsedSidebarSections.insert(section)
      } else {
        settings.collapsedSidebarSections.remove(section)
      }
    } label: {
      HStack(spacing: 4) {
        Text(title)
        Spacer(minLength: 0)
        Image(systemName: isExpanded(section) ? "chevron.down" : "chevron.right")
          .font(.caption2).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Hide from Sidebar") {
        if settings.isVisible(chrome) { settings.toggle(chrome) }
      }
      extra
    }
    .accessibilityValue(isExpanded(section) ? "Expanded" : "Collapsed")
    .accessibilityIdentifier("sidebarHeader.\(chrome.rawValue)")
  }

  @ViewBuilder private func volumeMenu(_ volume: MountedVolume) -> some View {
    let location = localProvider.location(for: volume.url)
    Button("Open in New Tab") { openInNewTab(location) }
    Button("Open in New Window") { openInNewWindow(["location": location]) }
    if volume.isEjectable {
      Divider()
      Button("Eject") { Task { await devices.eject(volume) } }
    }
    Divider()
    Button("Hide from Sidebar") {
      settings.hiddenSidebarItems.insert(SidebarItemKey.volume(volume))
    }
  }

  private func visibleFavorites(_ items: [FavoriteItem]) -> [FavoriteItem] {
    items.filter { !settings.hiddenSidebarItems.contains(SidebarItemKey.favorite($0)) }
  }

  /// Marks volumes that aren't this Mac's own disks. Internal disks get no badge.
  @ViewBuilder private func volumeBadge(_ volume: MountedVolume) -> some View {
    if !volume.isLocal {
      badge(symbol: "network", text: "Network volume")
    } else if !volume.isInternal {
      badge(symbol: "externaldrive", text: "External volume")
    }
  }

  private func badge(symbol: String, text: LocalizedStringKey) -> some View {
    Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
      .help(text).accessibilityLabel(text)
  }

  private func favoriteRow(_ item: FavoriteItem) -> some View {
    let symbol: String
    let kind: LocalizedStringKey
    if case .local = item.target {
      symbol = "folder"
      kind = "Local folder"
    } else {
      symbol = "network"
      kind = "Remote folder"
    }
    return Button {
      devices.selectedVolumeID = nil
      Task { await connections.openFavorite(item, in: browser) }
    } label: {
      Label(item.name, systemImage: symbol).lineLimit(1)
    }
    .buttonStyle(.plain)
    .help(kind)
    .accessibilityHint(kind)
    .contextMenu {
      Button("Open in New Tab") {
        browser.newTab(in: browser.activePaneID)
        Task { await connections.openFavorite(item, in: browser) }
      }
      Button("Open in New Window") { openInNewWindow(["favorite": item]) }
      Button("Reveal in Favorite Manager") { revealFavorite(item.id) }
      Divider()
      Button("Edit") { revealFavorite(item.id, edit: true) }
      Button("Delete") { favoriteToDelete = item }
      Button("Hide from Sidebar") {
        settings.hiddenSidebarItems.insert(SidebarItemKey.favorite(item))
      }
    }
    .accessibilityIdentifier("sidebarFavorite.\(item.name)")
  }

  private func revealFavorite(_ id: UUID?, edit: Bool = false) {
    favoriteManagerRequest = FavoriteManagerRequest(favorite: id, edits: edit)
  }

  private func openInNewTab(_ location: Location) {
    let id = browser.activePaneID
    browser.newTab(in: id)
    Task { await browser.navigate(to: location, in: id) }
  }

  private func openInNewWindow(_ target: [String: Any]) {
    NotificationCenter.default.post(name: .fileTermOpenInNewWindow, object: nil, userInfo: target)
  }

  private func open(_ location: Location) {
    let id = browser.activePaneID
    Task { await browser.navigate(to: location, in: id) }
  }

  /// Lists every local file with the tag, using Spotlight, as a closeable result scope.
  private func showFiles(tagged tag: FileTag) {
    let id = browser.activePaneID
    let provider = localProvider
    let includeHidden = settings.showHidden
    Task {
      if browser.pane(id).location?.providerID != provider.id {
        let home = provider.location(for: FileManager.default.homeDirectoryForCurrentUser)
        await browser.navigate(to: home, in: id)
      }
      let pane = browser.pane(id)
      pane.spotlightRunner = { search, root in
        try await SpotlightSearch.run(search, in: root, provider: provider).filter(tag.isOn)
      }
      let query = SearchQuery(
        text: tag.name, matchName: false, matchTag: true, includeHidden: includeHidden,
        engine: .spotlight)
      await pane.search(query, root: Location(providerID: provider.id, path: "/"))
    }
  }

  private func volumeInfo(_ volume: MountedVolume) -> String {
    let kind = volume.isInternal ? "Internal" : "Mounted"
    guard let available = volume.available, let capacity = volume.capacity else { return kind }
    return
      "\(available.formatted(.byteCount(style: .file))) free of \(capacity.formatted(.byteCount(style: .file)))"
  }

  @ViewBuilder private var previewPanel: some View {
    Group {
      if let entry = browser.activePane.selectedEntries.first,
        entry.location.providerID == localProvider.id
      {
        MetadataInspectorView(url: URL(fileURLWithPath: entry.location.path)) {
          Task { await browser.refreshAll() }
        }
      } else {
        ContentUnavailableView(
          "Preview", systemImage: "sidebar.right",
          description: Text("Select a local item to inspect its metadata and preview its contents.")
        )
        .frame(maxHeight: .infinity)
      }
    }.accessibilityIdentifier("panel.Preview")
  }

}

/// What a sidebar menu wants the Favorite Manager to show when it opens.
private struct FavoriteManagerRequest: Identifiable {
  let id = UUID()
  let favorite: UUID?
  let edits: Bool
}

private struct BrowserPaneView: View {
  @Bindable var pane: PaneModel
  let paneID: PaneID
  let browser: BrowserModel
  let settings: AppSettings
  let registry: CommandRegistry
  let localProvider: LocalFileSystemProvider
  let volumeService: any VolumeService
  @State private var status = PaneStatusModel()

  var body: some View {
    VStack(spacing: 0) {
      if settings.isVisible(.tabBar) {
        PaneTabBar(browser: browser, paneID: paneID, registry: registry)
        Divider()
      }
      if settings.isVisible(.pathBar) {
        PathBar(
          url: pane.location.flatMap { try? localProvider.url(for: $0) },
          displayPath: pane.location?.path
        ) { url in
          browser.activePaneID = paneID
          Task { await browser.navigate(to: localProvider.location(for: url), in: paneID) }
        }
        .frame(height: 30).padding(.horizontal, 8)
        Divider()
      }
      if let error = pane.errorMessage ?? pane.movedNotice {
        HStack {
          Label(
            deniedPermission.map { permissionMessage($0) } ?? error,
            systemImage: "exclamationmark.triangle"
          )
          .font(.callout).foregroundStyle(.secondary)
          .accessibilityIdentifier("navigationError")
          Spacer(minLength: 0)
          if let permission = deniedPermission {
            Button("Open System Settings") { NSWorkspace.shared.open(permission.settingsURL) }
              .controlSize(.small).accessibilityIdentifier("openPermissionSettings")
          }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        Divider()
      }
      SearchResultsBanner(pane: pane)
      fileList
      Divider()
      statusBar
    }
    .overlay {
      Rectangle().strokeBorder(
        browser.activePaneID == paneID ? Color.accentColor : Color.clear, lineWidth: 2
      ).allowsHitTesting(false)
    }
    .contentShape(Rectangle())
    .background(PaneActivationView { browser.activePaneID = paneID })
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pane.\(paneID.rawValue)")
    .accessibilityValue(browser.activePaneID == paneID ? "Active" : "Inactive")
    .task(id: pane.location) { await status.update(for: pane.location, service: volumeService) }
  }

  /// Only local folders are guarded by macOS permissions; a server's refusal has no setting here.
  private var deniedPermission: SystemPermission? {
    guard let denied = pane.deniedLocation, denied.providerID == localProvider.id else {
      return nil
    }
    return SystemPermission.required(forPath: denied.path)
  }

  private func permissionMessage(_ permission: SystemPermission) -> String {
    "macOS denied access to \(pane.deniedLocation?.path ?? "this folder"). "
      + "FileTerm needs the \(permission.title) permission."
  }

  private var statusBar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        itemCount
        if !pane.selection.isEmpty {
          Text(selectionSummary).accessibilityIdentifier("selectedSize")
        }
        Spacer(minLength: 0)
        Text(freeSpace).accessibilityIdentifier("freeSpace")
        if pane.isLoading { ProgressView().controlSize(.mini) }
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack {
          itemCount
          Spacer()
          if pane.isLoading { ProgressView().controlSize(.mini) }
        }
        Text(pane.selection.isEmpty ? freeSpace : "\(selectionSummary) · \(freeSpace)")
      }
    }
    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    .padding(.horizontal, 8).padding(.vertical, 6)
  }

  private var itemCount: some View {
    Text("\(pane.visibleEntries.count) items").accessibilityIdentifier("itemCount")
  }
  private var freeSpace: String {
    status.availableBytes.map { "\($0.formatted(.byteCount(style: .file))) free" }
      ?? "Free space unavailable"
  }
  private var selectionSummary: String {
    let size = pane.selectedBytes.formatted(.byteCount(style: .file))
    return
      "\(pane.selectedEntries.count) selected · \(size)\(pane.hasUnknownSelectedSizes ? " + unknown" : "")"
  }

  private var fileList: some View {
    FileContentView(
      pane: pane, paneID: paneID, browser: browser, provider: localProvider, registry: registry,
      settings: settings
    )
    .id(pane.id)
    .dropDestination(for: URL.self) { urls, _ in
      let files = urls.filter(\.isFileURL)
      guard !files.isEmpty, pane.location != nil, pane.searchScope == nil else { return false }
      NotificationCenter.default.post(
        name: .fileTermDropFiles, object: pane,
        userInfo: ["urls": files, "optionPressed": NSEvent.modifierFlags.contains(.option)])
      return true
    }
  }
}

private struct GoToFolderSheet: View {
  @Bindable var model: GoToFolderModel
  @Environment(\.dismiss) private var dismiss
  @FocusState private var pathFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Go to Folder").font(.headline)
      TextField("Absolute folder path", text: $model.path)
        .textFieldStyle(.roundedBorder).focused($pathFocused)
        .accessibilityIdentifier("goToFolderPath")
        .onSubmit { submit() }
        .onKeyPress(.tab) {
          guard let first = model.suggestions.first else { return .ignored }
          model.path = first
          return .handled
        }
      if let error = model.errorMessage {
        Text(error).foregroundStyle(.red).accessibilityIdentifier("goToFolderError")
      }
      if !model.suggestions.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(model.suggestions, id: \.self) { path in
            Button(path) {
              model.path = path
              submit()
            }
            .buttonStyle(.plain).lineLimit(1).truncationMode(.middle)
            .accessibilityIdentifier("goToFolderSuggestion.\(path)")
          }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") {
          model.cancel()
          dismiss()
        }.keyboardShortcut(.cancelAction)
        Button("Go") { submit() }.keyboardShortcut(.defaultAction).disabled(model.isSubmitting)
      }
    }.padding(20).frame(width: 480).onAppear { pathFocused = true }
  }

  private func submit() {
    Task { if await model.submit() { dismiss() } }
  }
}

extension GoToFolderModel: Identifiable {
  nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
extension Notification.Name {
  static let fileTermGoToFolder = Notification.Name("FileTerm.goToFolder")
  static let fileTermConnect = Notification.Name("FileTerm.connect")
  static let fileTermBrowserOptions = Notification.Name("FileTerm.browserOptions")
  static let fileTermQuickSelect = Notification.Name("FileTerm.quickSelect")
  static let fileTermSync = Notification.Name("FileTerm.sync")
  static let fileTermBatchRename = Notification.Name("FileTerm.batchRename")
  static let fileTermRenamePreset = Notification.Name("FileTerm.renamePreset")
  static let fileTermQuickOpen = Notification.Name("FileTerm.quickOpen")
  static let fileTermFind = Notification.Name("FileTerm.find")
  static let fileTermDropFiles = Notification.Name("FileTerm.dropFiles")
  static let fileTermOpenInNewWindow = Notification.Name("FileTerm.openInNewWindow")
}
