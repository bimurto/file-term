import AppKit
import FileTermCore
import SwiftUI

private struct IconFramesKey: PreferenceKey {
  static let defaultValue: [Location: CGRect] = [:]
  static func reduce(value: inout [Location: CGRect], nextValue: () -> [Location: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

struct FileContentView: View {
  @Bindable var pane: PaneModel
  let paneID: PaneID
  let browser: BrowserModel
  let provider: LocalFileSystemProvider
  let registry: CommandRegistry
  let settings: AppSettings
  @Environment(CloudFileActions.self) private var cloudFiles: CloudFileActions?
  @State private var anchor: Location?
  private static let iconGridSpace = "iconGridContent"
  @FocusState private var iconGridFocused: Bool
  @State private var iconFrames: [Location: CGRect] = [:]
  @State private var rubberBand: CGRect?
  @State private var rubberBandBase: Set<Location> = []
  @State private var typeSelect = TypeSelectBuffer()

  var body: some View {
    Group {
      switch pane.viewOptions.mode {
      case .list: fileList
      case .icons: iconGrid
      case .columns:
        HierarchyColumnsView(
          pane: pane, provider: provider, open: open, select: select)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      FileContextMenuHost(
        pane: pane, paneID: paneID, browser: browser, registry: registry, settings: settings,
        cloudFiles: cloudFiles)
    )
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

  private var columnCustomization: Binding<TableColumnCustomization<FileEntry>> {
    Binding(get: { settings.listColumns }, set: { settings.listColumns = $0 })
  }

  private var fileList: some View {
    Table(
      of: FileEntry.self, selection: $pane.selection, sortOrder: sortOrder,
      columnCustomization: columnCustomization
    ) {
      TableColumn("Name", sortUsing: EntryOrder(field: .name)) { entry in
        HStack(spacing: 6) {
          FileIcon(entry: entry, localProvider: provider)
          InlineFileName(pane: pane, entry: entry).lineLimit(1)
        }
        .opacity(entry.isHidden ? 0.5 : 1)
        .accessibilityValue(entry.isHidden ? "Hidden" : "")
      }.width(min: 100, ideal: 220)
        .customizationID("name").disabledCustomizationBehavior(.visibility)
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
    .contextMenu(forSelectionType: Location.self) { _ in
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
    }.width(70).customizationID("size")
    TableColumn("Kind", sortUsing: EntryOrder(field: .kind)) { Text($0.kindLabel) }.width(100)
      .customizationID("kind")
    TableColumn("Modified", sortUsing: EntryOrder(field: .modified)) { Text(date($0.modifiedAt)) }
      .width(160).customizationID("modified")
    TableColumn("Created", sortUsing: EntryOrder(field: .created)) { Text(date($0.createdAt)) }
      .width(160).customizationID("created")
    TableColumn("Added", sortUsing: EntryOrder(field: .added)) { Text(date($0.addedAt)) }.width(160)
      .customizationID("added")
    TableColumn("Last Opened", sortUsing: EntryOrder(field: .opened)) { Text(date($0.openedAt)) }
      .width(160).customizationID("opened")
    TableColumn("Tags", sortUsing: EntryOrder(field: .tags)) {
      Text($0.tags.joined(separator: ", "))
    }.width(120).customizationID("tags")
    TableColumn("Owner", sortUsing: EntryOrder(field: .owner)) { Text($0.owner ?? "—") }.width(100)
      .customizationID("owner")
    TableColumn("Group", sortUsing: EntryOrder(field: .group)) { Text($0.group ?? "—") }.width(100)
      .customizationID("group")
    TableColumn("Permissions", sortUsing: EntryOrder(field: .permissions)) { entry in
      Text(entry.permissions.map { String(format: "%03o", $0) } ?? "—")
    }.width(100).customizationID("permissions")
  }

  private func date(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
  }

  private var iconGrid: some View {
    GeometryReader { viewport in
      ScrollViewReader { scroller in
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
                    if pane.viewOptions.showsIconSize, let size = entry.size {
                      Text(size.formatted(.byteCount(style: .file)))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityIdentifier("iconSize.\(entry.name)")
                    }
                  }
                  .opacity(entry.isHidden ? 0.5 : 1)
                  .padding(8).frame(maxWidth: .infinity, minHeight: 88)
                  .background(
                    pane.selection.contains(entry.id) ? Color.accentColor.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                  )
                  .background {
                    GeometryReader { item in
                      Color.clear.preference(
                        key: IconFramesKey.self,
                        value: [entry.id: item.frame(in: .named(Self.iconGridSpace))])
                    }
                  }
                  .contentShape(Rectangle())
                  .onTapGesture(count: 2) {
                    guard pane.renamingLocation != entry.location else { return }
                    open(entry)
                  }
                  .onTapGesture {
                    guard pane.renamingLocation != entry.location else { return }
                    select(entry)
                  }
                  .background(ContextMenuAnchor(entry: entry, pane: pane, open: open))
                  .onDrag { fileDragProvider(entry) ?? NSItemProvider() }
                  .accessibilityElement(children: .contain)
                  .accessibilityIdentifier("icon.\(entry.name)")
                  .accessibilityAction(named: "Open") { open(entry) }
                  .help(entry.location.path)
                }
              }.padding(.horizontal, 8)
            }
          }
          .padding(.vertical, 12)
          .frame(
            maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading
          )
          .background { rubberBandSurface }
          .overlay(alignment: .topLeading) {
            if let band = rubberBand {
              Rectangle().fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().stroke(Color.accentColor))
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
                .allowsHitTesting(false)
            }
          }
          .coordinateSpace(.named(Self.iconGridSpace))
          .onPreferenceChange(IconFramesKey.self) { frames in
            MainActor.assumeIsolated { iconFrames = frames }
          }
        }
        .accessibilityIdentifier("iconGrid")
        .focusable()
        .focusEffectDisabled()
        .focused($iconGridFocused)
        .onAppear { iconGridFocused = browser.activePaneID == paneID }
        .onMoveCommand { direction in moveIconSelection(direction, scroller) }
        .onKeyPress(phases: .down) { press in typeToSelect(press, scroller) }
      }
    }
  }

  /// Sits behind the icons, so a drag that starts on an icon stays a file drag.
  private var rubberBandSurface: some View {
    Color.clear.contentShape(Rectangle()).gesture(
      DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.iconGridSpace))
        .onChanged { drag in
          if rubberBand == nil {
            browser.activePaneID = paneID
            iconGridFocused = true
            let adds = !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift])
            rubberBandBase = adds ? pane.selection : []
          }
          let band = CGRect(
            x: min(drag.startLocation.x, drag.location.x),
            y: min(drag.startLocation.y, drag.location.y),
            width: abs(drag.location.x - drag.startLocation.x),
            height: abs(drag.location.y - drag.startLocation.y))
          rubberBand = band
          pane.selection = rubberBandBase.union(
            IconGridNavigation.selection(in: band, frames: iconFrames))
        }
        .onEnded { _ in rubberBand = nil })
  }

  private func moveIconSelection(_ direction: MoveCommandDirection, _ scroller: ScrollViewProxy) {
    let move: IconGridNavigation.Direction
    switch direction {
    case .left: move = .left
    case .right: move = .right
    case .up: move = .up
    case .down: move = .down
    @unknown default: return
    }
    let groups = pane.entryGroups.map { $0.entries.map(\.id) }
    let current = anchor.flatMap { pane.selection.contains($0) ? $0 : nil } ?? pane.selection.first
    guard
      let target = IconGridNavigation.move(
        from: current, move, groups: groups, columns: IconGridNavigation.columns(in: iconFrames))
    else { return }
    selectIcon(target, scroller)
  }

  private func typeToSelect(_ press: KeyPress, _ scroller: ScrollViewProxy) -> KeyPress.Result {
    guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
      let character = press.characters.first,
      character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        || (character == " " && typeSelect.isTyping()),
      pane.renamingLocation == nil
    else { return .ignored }
    let typed = typeSelect.append(press.characters)
    if let match = IconGridNavigation.match(typed, in: pane.entryGroups.flatMap(\.entries)) {
      selectIcon(match, scroller)
    }
    return .handled
  }

  private func selectIcon(_ location: Location, _ scroller: ScrollViewProxy) {
    browser.activePaneID = paneID
    anchor = location
    pane.selection = [location]
    scroller.scrollTo(location)
  }

  private func select(_ entry: FileEntry) {
    browser.activePaneID = paneID
    iconGridFocused = true
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
    } else if browser.onOpenFile?(entry) == true {
      return
    } else if let url = try? provider.url(for: entry.location) {
      NSWorkspace.shared.open(url)
    } else {
      pane.selection = [entry.id]
      registry.execute("file.open")
    }
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
                        .background(ContextMenuAnchor(entry: entry, pane: pane, open: open))
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
