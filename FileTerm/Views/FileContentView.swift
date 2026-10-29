import AppKit
import FileTermCore
import SwiftUI

struct FileContentView: View {
  @Bindable var pane: PaneModel
  let paneID: PaneID
  let browser: BrowserModel
  let provider: LocalFileSystemProvider
  /// Handles a file the user opens before it goes to the system, e.g. extracting an archive.
  var openFile: (FileEntry) -> Bool = { _ in false }
  @State private var anchor: Location?

  var body: some View {
    Group {
      switch pane.viewOptions.mode {
      case .list: fileList
      case .icons: iconGrid
      case .columns:
        HierarchyColumnsView(
          pane: pane, provider: provider, open: open, select: select,
          showPackageContents: showPackageContents)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
      if pane.visibleEntries.isEmpty && !pane.isLoading && !(pane.searchScope?.isRunning ?? false) {
        ContentUnavailableView(
          pane.searchScope != nil
            ? "No results" : pane.location == nil ? "No folder open" : "This folder is empty",
          systemImage: pane.searchScope != nil ? "magnifyingglass" : "folder"
        )
        .allowsHitTesting(false)
      }
    }
  }

  private var sortOrder: Binding<[EntryOrder]> {
    Binding(
      get: { [pane.viewOptions.order] },
      set: { values in
        guard let first = values.first else { return }
        pane.viewOptions.sortField = first.field
        pane.viewOptions.descending = first.order == .reverse
      })
  }

  private var fileList: some View {
    Table(of: FileEntry.self, selection: $pane.selection, sortOrder: sortOrder) {
      TableColumn("Name", sortUsing: EntryOrder(field: .name)) { entry in
        HStack(spacing: 6) {
          FileIcon(entry: entry, localProvider: provider)
          InlineFileName(pane: pane, entry: entry).lineLimit(1)
        }
        .opacity(entry.isHidden ? 0.5 : 1)
        .accessibilityValue(entry.isHidden ? "Hidden" : "")
      }.width(min: 100, ideal: 220)
      metadataColumns
    } rows: {
      if pane.viewOptions.groupField == .none {
        ForEach(pane.displayEntries) { entry in
          TableRow(entry).itemProvider { fileDragProvider(entry) }
        }
      } else {
        ForEach(pane.entryGroups) { group in
          Section {
            ForEach(group.entries) { entry in
              TableRow(entry).itemProvider { fileDragProvider(entry) }
            }
          } header: {
            Text(group.title ?? "").accessibilityIdentifier("groupHeader." + (group.title ?? "all"))
          }
        }
      }
    }
    .contextMenu(forSelectionType: Location.self) { locations in
      if locations.count == 1, let location = locations.first,
        let entry = pane.visibleEntries.first(where: { $0.location == location })
      {
        FileEntryContextMenu(
          pane: pane, entry: entry, provider: provider, open: open,
          showPackageContents: showPackageContents)
      }
    } primaryAction: { locations in
      if locations.count > 1 {
        // Return with several items selected opens Batch Rename.
        NotificationCenter.default.post(name: .init("FileTerm.BeginRename"), object: pane)
        return
      }
      guard locations.count == 1, let location = locations.first,
        let entry = pane.visibleEntries.first(where: { $0.location == location })
      else { return }
      open(entry)
    }
    .accessibilityIdentifier("fileList")
  }

  @TableColumnBuilder<FileEntry, EntryOrder>
  private var metadataColumns: some TableColumnContent<FileEntry, EntryOrder> {
    TableColumn("Size", sortUsing: EntryOrder(field: .size)) { entry in
      Text(entry.size.map { $0.formatted(.byteCount(style: .file)) } ?? "—").monospacedDigit()
    }.width(70)
    TableColumn("Kind", sortUsing: EntryOrder(field: .kind)) { Text($0.kindLabel) }.width(100)
    TableColumn("Modified", sortUsing: EntryOrder(field: .modified)) { Text(date($0.modifiedAt)) }
      .width(160)
    TableColumn("Created", sortUsing: EntryOrder(field: .created)) { Text(date($0.createdAt)) }
      .width(160)
    TableColumn("Added", sortUsing: EntryOrder(field: .added)) { Text(date($0.addedAt)) }.width(160)
    TableColumn("Last Opened", sortUsing: EntryOrder(field: .opened)) { Text(date($0.openedAt)) }
      .width(160)
    TableColumn("Tags", sortUsing: EntryOrder(field: .tags)) {
      Text($0.tags.joined(separator: ", "))
    }.width(120)
    TableColumn("Owner", sortUsing: EntryOrder(field: .owner)) { Text($0.owner ?? "—") }.width(100)
    TableColumn("Group", sortUsing: EntryOrder(field: .group)) { Text($0.group ?? "—") }.width(100)
    TableColumn("Permissions", sortUsing: EntryOrder(field: .permissions)) { entry in
      Text(entry.permissions.map { String(format: "%03o", $0) } ?? "—")
    }.width(100)
  }

  private func date(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
  }

  private var iconGrid: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        ForEach(pane.entryGroups) { group in
          if let title = group.title { Text(title).font(.headline).padding(.horizontal, 12) }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 130))], spacing: 12) {
            ForEach(group.entries) { entry in
              VStack(spacing: 6) {
                FileIcon(entry: entry, localProvider: provider, size: 48)
                InlineFileName(pane: pane, entry: entry)
                  .font(.callout).lineLimit(2).multilineTextAlignment(.center)
              }
              .opacity(entry.isHidden ? 0.5 : 1)
              .padding(8).frame(maxWidth: .infinity, minHeight: 88)
              .background(
                pane.selection.contains(entry.id) ? Color.accentColor.opacity(0.2) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
              )
              .contentShape(Rectangle())
              .onTapGesture(count: 2) {
                guard pane.renamingLocation != entry.location else { return }
                open(entry)
              }
              .onTapGesture {
                guard pane.renamingLocation != entry.location else { return }
                select(entry)
              }
              .contextMenu {
                FileEntryContextMenu(
                  pane: pane, entry: entry, provider: provider, open: open,
                  showPackageContents: showPackageContents)
              }
              .onDrag { fileDragProvider(entry) ?? NSItemProvider() }
              .accessibilityElement(children: .contain)
              .accessibilityIdentifier("icon.\(entry.name)")
              .accessibilityAction(named: "Open") { open(entry) }
              .help(entry.location.path)
            }
          }.padding(.horizontal, 8)
        }
      }.padding(.vertical, 12)
    }.accessibilityIdentifier("iconGrid")
  }

  private func select(_ entry: FileEntry) {
    browser.activePaneID = paneID
    if NSEvent.modifierFlags.contains(.shift), let anchor = anchor ?? pane.selection.first {
      let ordered = pane.entryGroups.flatMap(\.entries).map(\.id)
      if let start = ordered.firstIndex(of: anchor), let end = ordered.firstIndex(of: entry.id) {
        let range = min(start, end)...max(start, end)
        pane.selection = Set(ordered[range])
        return
      }
    }
    anchor = entry.id
    if NSEvent.modifierFlags.contains(.command) {
      if pane.selection.contains(entry.id) {
        pane.selection.remove(entry.id)
      } else {
        pane.selection.insert(entry.id)
      }
    } else {
      pane.selection = [entry.id]
    }
  }

  private func open(_ entry: FileEntry) {
    browser.activePaneID = paneID
    guard pane.renamingLocation != entry.location else { return }
    if entry.kind == .directory && !isPackage(entry, provider: provider) {
      Task { await browser.enterFolder(entry.location, in: paneID) }
    } else if openFile(entry) {
      return
    } else if let url = try? provider.url(for: entry.location) {
      NSWorkspace.shared.open(url)
    }
  }

  private func showPackageContents(_ entry: FileEntry) {
    browser.activePaneID = paneID
    Task { await browser.enterFolder(entry.location, in: paneID) }
  }
}

/// Export file URLs so the terminal can insert quoted paths without submitting commands.
private func fileDragProvider(_ entry: FileEntry) -> NSItemProvider? {
  guard entry.location.providerID == "local" else { return nil }
  return NSItemProvider(object: URL(fileURLWithPath: entry.location.path) as NSURL)
}

private func isPackage(_ entry: FileEntry, provider: LocalFileSystemProvider) -> Bool {
  guard let url = try? provider.url(for: entry.location) else { return false }
  return url.pathExtension.lowercased() == "app"
    || NSWorkspace.shared.isFilePackage(atPath: url.path)
}

private struct FileEntryContextMenu: View {
  let pane: PaneModel
  let entry: FileEntry
  let provider: LocalFileSystemProvider
  let open: (FileEntry) -> Void
  let showPackageContents: (FileEntry) -> Void

  var body: some View {
    Button("Open") { open(entry) }
    Button("Rename") {
      pane.selection = [entry.id]
      NotificationCenter.default.post(name: .init("FileTerm.BeginRename"), object: pane)
    }
    if isPackage(entry, provider: provider) {
      Button("Show Package Contents") { showPackageContents(entry) }
    }
  }
}

private struct HierarchyColumn: Identifiable {
  var id: Location { location }
  let location: Location
  let entries: [FileEntry]
  let selectedChild: Location?
  let error: String?
}

private struct HierarchyColumnsView: View {
  @Bindable var pane: PaneModel
  let provider: LocalFileSystemProvider
  let open: (FileEntry) -> Void
  let select: (FileEntry) -> Void
  let showPackageContents: (FileEntry) -> Void
  @State private var columns: [HierarchyColumn] = []
  @State private var root: Location?

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 0) {
            ForEach(columns) { column in
              VStack(alignment: .leading, spacing: 0) {
                Text(
                  URL(fileURLWithPath: column.location.path).lastPathComponent.isEmpty
                    ? "/" : URL(fileURLWithPath: column.location.path).lastPathComponent
                )
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(height: 28, alignment: .leading).padding(.horizontal, 8)
                Divider()
                if let error = column.error { Text(error).font(.caption).padding(8) }
                List {
                  ForEach(
                    EntryGrouping.groups(
                      column.location == pane.location ? pane.visibleEntries : column.entries,
                      by: pane.viewOptions.groupField, order: pane.viewOptions.order)
                  ) { group in
                    Section {
                      ForEach(group.entries) { entry in
                        HStack(spacing: 6) {
                          FileIcon(entry: entry, localProvider: provider)
                          InlineFileName(pane: pane, entry: entry).lineLimit(1)
                          Spacer(minLength: 0)
                          if entry.kind == .directory && !isPackage(entry, provider: provider) {
                            Image(systemName: "chevron.right").font(.caption2)
                          }
                        }
                        .padding(.vertical, 3).contentShape(Rectangle())
                        .opacity(entry.isHidden ? 0.5 : 1)
                        .background(
                          column.selectedChild == entry.location
                            || pane.selection.contains(entry.id)
                            ? Color.accentColor.opacity(0.2) : .clear
                        )
                        .onTapGesture(count: 2) {
                          guard pane.renamingLocation != entry.location else { return }
                          open(entry)
                        }
                        .onTapGesture {
                          guard pane.renamingLocation != entry.location else { return }
                          if entry.kind == .directory && !isPackage(entry, provider: provider) {
                            open(entry)
                          } else {
                            select(entry)
                          }
                        }
                        .contextMenu {
                          FileEntryContextMenu(
                            pane: pane, entry: entry, provider: provider, open: open,
                            showPackageContents: showPackageContents)
                        }
                        .onDrag { fileDragProvider(entry) ?? NSItemProvider() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(entry.name)
                        .accessibilityAction {
                          if entry.kind == .directory && !isPackage(entry, provider: provider) {
                            open(entry)
                          } else {
                            select(entry)
                          }
                        }
                        .accessibilityAction(named: "Open") { open(entry) }
                      }
                    } header: {
                      if let title = group.title { Text(title) }
                    }
                  }
                }.listStyle(.plain)
              }.frame(width: 220).id(column.location)
              Divider()
            }
          }.frame(height: geometry.size.height)
        }
        .task(id: pane.location) {
          guard let location = pane.location else {
            columns = []
            return
          }
          var ancestors = [location]
          let root = self.root ?? location
          while ancestors.first != root, let parent = ancestors.first?.parent {
            ancestors.insert(parent, at: 0)
          }
          if ancestors.first != root {
            ancestors = [location]
            self.root = location
          } else {
            self.root = root
          }
          var result: [HierarchyColumn] = []
          for (index, ancestor) in ancestors.enumerated() {
            do {
              let entries: [FileEntry]
              if ancestor == location {
                entries = pane.entries
              } else if let cached = columns.first(where: { $0.location == ancestor }) {
                entries = cached.entries
              } else {
                entries = try await provider.list(ancestor)
              }
              result.append(
                HierarchyColumn(
                  location: ancestor, entries: entries,
                  selectedChild: index + 1 < ancestors.count ? ancestors[index + 1] : nil,
                  error: nil)
              )
            } catch {
              result.append(
                HierarchyColumn(
                  location: ancestor, entries: [], selectedChild: nil,
                  error: error.localizedDescription))
            }
            guard !Task.isCancelled else { return }
          }
          guard pane.location == location else { return }
          columns = result
        }
        .onChange(of: columns.map(\.location)) { _, _ in
          if let location = pane.location { proxy.scrollTo(location, anchor: .trailing) }
        }
      }
    }.accessibilityIdentifier("columnBrowser")
  }
}

struct FileIcon: View {
  let entry: FileEntry
  let localProvider: LocalFileSystemProvider
  var size: CGFloat = 16
  @State private var icon: NSImage?

  var body: some View {
    Group {
      if let icon {
        Image(nsImage: icon).resizable()
      } else {
        Image(systemName: entry.kind == .directory ? "folder" : "doc").resizable()
      }
    }
    .frame(width: size, height: size).accessibilityHidden(true)
    .task(id: entry.location) {
      guard let url = try? localProvider.url(for: entry.location) else { return }
      icon = NSWorkspace.shared.icon(forFile: url.path)
    }
  }
}
