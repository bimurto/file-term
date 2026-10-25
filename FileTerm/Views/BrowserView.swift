import AppKit
import FileTermCore
import SwiftUI

struct BrowserView: View {
  @Bindable var browser: BrowserModel
  let settings: AppSettings
  let registry: CommandRegistry
  let localProvider: LocalFileSystemProvider
  let devices: DeviceModel
  @State private var goToFolder: GoToFolderModel?
  @State private var optionsSheet: BrowserOptionsSheet?
  @State private var quickSelectShown = false
  @State private var quickOpenShown = false
  @State private var pendingQuickOpen: QuickOpenItem?
  @State private var searchQuery = SearchQuery()
  @FocusState private var searchFocused: Bool
  @State private var extensionPoints = QuickOpenExtensionPoints()

  var body: some View {
    VStack(spacing: 0) {
      if settings.isVisible(.toolbar) {
        toolbar
        Divider()
      }
      if let notice = browser.notice {
        HStack {
          Label(notice, systemImage: "info.circle").font(.callout)
          Spacer()
          Button("Dismiss") { browser.dismissNotice() }
        }
        .padding(8).accessibilityIdentifier("browserNotice")
        Divider()
      }
      HSplitView {
        if settings.isVisible(.sidebar) {
          sidebar.frame(minWidth: 120, idealWidth: 170, maxWidth: 220)
        }
        paneLayout
        if settings.isVisible(.preview) {
          previewPanel.frame(minWidth: 300, idealWidth: 320, maxWidth: 440)
        }
      }
      if settings.isVisible(.activities) || settings.isVisible(.logs) {
        Divider()
        HSplitView {
          if settings.isVisible(.activities) { placeholder(.activities) }
          if settings.isVisible(.logs) { placeholder(.logs) }
        }.frame(height: 140)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .frame(minWidth: 680, minHeight: 420)
    .onReceive(NotificationCenter.default.publisher(for: .fileTermGoToFolder)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      goToFolder = GoToFolderModel(
        browser: browser, provider: localProvider, paneID: browser.activePaneID)
    }
    .sheet(item: $goToFolder) { model in GoToFolderSheet(model: model) }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermQuickSelect)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      quickSelectShown = true
    }
    .sheet(isPresented: $quickSelectShown) { QuickSelectSheet(pane: browser.activePane) }
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
    .onReceive(NotificationCenter.default.publisher(for: .fileTermFind)) { notification in
      guard notification.object as? BrowserModel === browser else { return }
      searchFocused = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .fileTermBrowserOptions)) { notification in
      guard notification.object as? BrowserModel === browser,
        let kind = notification.userInfo?["kind"] as? String
      else { return }
      optionsSheet = BrowserOptionsSheet(rawValue: kind)
    }
    .sheet(item: $optionsSheet) { sheet in
      switch sheet {
      case .viewOptions: ViewOptionsSheet(pane: browser.activePane)
      case .toolbar: ToolbarCustomizationSheet(settings: settings, registry: registry)
      case .sidebar: SidebarEditorSheet(settings: settings)
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

  private var toolbar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 6) {
        ForEach(settings.workspace.toolbarItems.filter { registry.command($0) != nil }, id: \.self)
        { id in
          commandButton(id, symbol: ToolbarSymbols.symbol(for: id))
        }
        Spacer(minLength: 0)
        Toggle(
          "Show hidden",
          isOn: Binding(
            get: { settings.showHidden },
            set: { value in
              settings.showHidden = value
              Task { await browser.setShowHidden(value) }
            })
        )
        .toggleStyle(.checkbox).fixedSize().accessibilityIdentifier("showHiddenToggle")
        FindToolbar(
          browser: browser, settings: settings, localProvider: localProvider, query: $searchQuery,
          focus: $searchFocused)
      }.padding(.horizontal, 10).frame(height: 44)
    }.scrollIndicators(.hidden).frame(height: 44)
  }

  private var quickOpenSources: [any QuickOpenSource] {
    let registry = registry
    let browser = browser
    let settings = settings
    let provider = localProvider
    let commands = ClosureQuickOpenSource {
      registry.commands.filter { !$0.id.hasPrefix("go.recent") && $0.id != "quickOpen" }
        .map { command in
          let shortcut = registry.effectiveShortcut(for: command.id)?.display
          let reason = registry.disabledReason(for: command.id)
          return QuickOpenItem(
            id: "command:" + command.id, title: command.title,
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

  private func commandButton(_ id: String, symbol: String) -> some View {
    let title = registry.command(id)?.title ?? id
    return Button {
      registry.execute(id)
    } label: {
      Image(systemName: symbol).frame(width: 20, height: 20)
    }
    .buttonStyle(.borderless).padding(3)
    .foregroundStyle(registry.isChecked(id) ? Color.accentColor : Color.primary)
    .background(
      registry.isChecked(id) ? Color.accentColor.opacity(0.12) : .clear,
      in: RoundedRectangle(cornerRadius: 4)
    )
    .disabled(registry.disabledReason(for: id) != nil)
    .help(registry.disabledReason(for: id) ?? title)
    .accessibilityLabel(title).accessibilityIdentifier(id)
    .accessibilityValue(registry.isChecked(id) ? "Shown" : "Hidden")
  }

  private var sidebar: some View {
    List {
      ForEach(settings.workspace.sidebarOrder, id: \.self) { section in
        if section == "devices" && settings.isVisible(.devices) {
          Section("Devices") {
            ForEach(devices.volumes) { volume in
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
                }.padding(.vertical, 3).contentShape(Rectangle())
                  .background(
                    devices.selectedVolumeID == volume.id ? Color.accentColor.opacity(0.15) : .clear
                  )
              }.buttonStyle(.plain).help(volume.url.path)
            }
          }
        }
        if section == "recents" && settings.isVisible(.recentFolders) {
          Section("Recent Folders") {
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
        }
      }
    }.listStyle(.sidebar).accessibilityIdentifier("navigationSidebar")
  }

  private func open(_ location: Location) {
    let id = browser.activePaneID
    Task { await browser.navigate(to: location, in: id) }
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
      }
    }.accessibilityIdentifier("panel.Preview")
  }

  private func placeholder(_ panel: PlaceholderPanel) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(panel.rawValue, systemImage: panel.symbol).font(.headline)
      Text("\(panel.rawValue) is not implemented yet.").foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityIdentifier("panel.\(panel.rawValue)")
  }
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
      if let error = pane.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.callout).foregroundStyle(.secondary)
          .padding(8).frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("navigationError")
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
    FileContentView(pane: pane, paneID: paneID, browser: browser, provider: localProvider)
      .id(pane.id)
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
      if let error = model.errorMessage {
        Text(error).foregroundStyle(.red).accessibilityIdentifier("goToFolderError")
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
  static let fileTermBrowserOptions = Notification.Name("FileTerm.browserOptions")
  static let fileTermQuickSelect = Notification.Name("FileTerm.quickSelect")
  static let fileTermQuickOpen = Notification.Name("FileTerm.quickOpen")
  static let fileTermFind = Notification.Name("FileTerm.find")
}
