import AppKit
import FileTermCore
import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
  @Bindable var browser: BrowserModel
  let settings: AppSettings
  let registry: CommandRegistry
  let localProvider: LocalFileSystemProvider
  let devices: DeviceModel
  @State private var goToFolder: GoToFolderModel?

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
        sidebar.frame(minWidth: 120, idealWidth: 170, maxWidth: 220)
        paneLayout
        if settings.isVisible(.preview) {
          placeholder(.preview).frame(minWidth: 140, idealWidth: 220)
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
    .background(.background)
    .frame(minWidth: 680, minHeight: 420)
    .onReceive(NotificationCenter.default.publisher(for: .fileTermGoToFolder)) { _ in
      goToFolder = GoToFolderModel(
        browser: browser, provider: localProvider, paneID: browser.activePaneID)
    }
    .sheet(item: $goToFolder) { model in
      GoToFolderSheet(model: model)
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
      settings: settings, localProvider: localProvider, volumeService: devices.service
    )
    .frame(minWidth: 220, minHeight: 130)
  }

  private var toolbar: some View {
    HStack(spacing: 6) {
      commandButton("go.back", symbol: "chevron.left")
      commandButton("go.forward", symbol: "chevron.right")
      commandButton("go.enclosingFolder", symbol: "arrow.up")
      Divider().frame(height: 20)
      commandButton("view.single", symbol: "rectangle")
      commandButton("view.vertical", symbol: "rectangle.split.2x1")
      commandButton("view.horizontal", symbol: "rectangle.split.1x2")
      commandButton("go.syncBrowsing", symbol: "link")
      commandButton("go.toFolder", symbol: "folder.badge.gearshape")
      Spacer(minLength: 6)
      ForEach(PlaceholderPanel.allCases) { panel in
        commandButton(panel.commandID, symbol: panel.symbol)
      }
    }.padding(.horizontal, 10).frame(height: 44)
  }

  private func commandButton(_ id: String, symbol: String) -> some View {
    let title = registry.command(id)?.title ?? id
    return Button {
      registry.execute(id)
    } label: {
      Image(systemName: symbol).frame(width: 20, height: 20)
    }
    .tint(registry.isChecked(id) ? .accentColor : nil)
    .disabled(registry.disabledReason(for: id) != nil)
    .help(registry.disabledReason(for: id) ?? title)
    .accessibilityLabel(title).accessibilityIdentifier(id)
    .accessibilityValue(registry.isChecked(id) ? "Shown" : "Hidden")
  }

  private var sidebar: some View {
    List {
      if settings.isVisible(.devices) {
        Section("Devices") {
          ForEach(devices.volumes) { volume in
            Button {
              devices.selectedVolumeID = volume.id
              open(localProvider.location(for: volume.url))
            } label: {
              HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: volume.url.path))
                  .resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                  Text(volume.name).lineLimit(1)
                  if settings.isVisible(.deviceInfo) {
                    Text(volumeInfo(volume)).font(.caption2).foregroundStyle(.secondary)
                  }
                }
                Spacer(minLength: 0)
              }
              .padding(.vertical, 3)
              .contentShape(Rectangle())
              .background(
                devices.selectedVolumeID == volume.id ? Color.accentColor.opacity(0.15) : .clear)
            }.buttonStyle(.plain).help(volume.url.path)
          }
        }
      }
      Section("Recent Folders") {
        ForEach(settings.recentFolders, id: \.self) { path in
          Button {
            devices.selectedVolumeID = nil
            open(Location(providerID: localProvider.id, path: path))
          } label: {
            Label(
              URL(fileURLWithPath: path).lastPathComponent.isEmpty
                ? "/" : URL(fileURLWithPath: path).lastPathComponent,
              systemImage: "folder"
            ).lineLimit(1)
          }.buttonStyle(.plain).help(path)
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
  let localProvider: LocalFileSystemProvider
  let volumeService: any VolumeService
  @State private var status = PaneStatusModel()

  var body: some View {
    VStack(spacing: 0) {
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
    Text("\(pane.entries.count) items").accessibilityIdentifier("itemCount")
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
}
