import AppKit
import FileTermCore
import SwiftUI

struct FileContentView: View {
  @Bindable var pane: PaneModel
  let paneID: PaneID
  let browser: BrowserModel
  let provider: LocalFileSystemProvider

  var body: some View {
    Group {
      switch pane.viewOptions.mode {
      case .list: fileList
      case .icons: iconGrid
      case .columns: HierarchyColumnsView(pane: pane, provider: provider, open: open)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
      if pane.entries.isEmpty && !pane.isLoading {
        ContentUnavailableView(
          pane.location == nil ? "No folder open" : "This folder is empty", systemImage: "folder"
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
          Text(entry.name).lineLimit(1)
        }
      }.width(min: 100, ideal: 220)
      metadataColumns
    } rows: {
      if pane.viewOptions.groupField == .none {
        ForEach(pane.displayEntries) { TableRow($0) }
      } else {
        ForEach(pane.entryGroups) { group in
          Section {
            ForEach(group.entries) { TableRow($0) }
          } header: {
            Text(group.title ?? "").accessibilityIdentifier("groupHeader." + (group.title ?? "all"))
          }
        }
      }
    }
    .contextMenu(forSelectionType: Location.self) { _ in
      EmptyView()
    } primaryAction: { locations in
      guard locations.count == 1, let location = locations.first,
        let entry = pane.entries.first(where: { $0.location == location })
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
                Text(entry.name).font(.callout).lineLimit(2).multilineTextAlignment(.center)
              }
              .padding(8).frame(maxWidth: .infinity, minHeight: 88)
              .background(
                pane.selection.contains(entry.id) ? Color.accentColor.opacity(0.2) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
              )
              .contentShape(Rectangle())
              .onTapGesture(count: 2) { open(entry) }
              .onTapGesture { select(entry) }
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
    if entry.kind == .directory {
      Task { await browser.enterFolder(entry.location, in: paneID) }
    } else if let parent = entry.location.parent, parent != pane.location {
      Task {
        if await browser.navigate(to: parent, in: paneID) {
          browser.pane(paneID).selection = [entry.id]
        }
      }
    } else {
      select(entry)
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
                      column.location == pane.location ? pane.entries : column.entries,
                      by: pane.viewOptions.groupField, order: pane.viewOptions.order)
                  ) { group in
                    Section {
                      ForEach(group.entries) { entry in
                        Button {
                          open(entry)
                        } label: {
                          HStack(spacing: 6) {
                            FileIcon(entry: entry, localProvider: provider)
                            Text(entry.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if entry.kind == .directory {
                              Image(systemName: "chevron.right").font(.caption2)
                            }
                          }
                          .padding(.vertical, 3).contentShape(Rectangle())
                          .background(
                            column.selectedChild == entry.location
                              || pane.selection.contains(entry.id)
                              ? Color.accentColor.opacity(0.2) : .clear)
                        }.buttonStyle(.plain)
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
