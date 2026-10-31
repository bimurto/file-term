import AppKit
import FileTermCore
import SwiftUI

struct FavoritesManagerSheet: View {
  @Bindable var settings: AppSettings
  let connections: ConnectionCoordinator
  let browser: BrowserModel
  /// What a sidebar menu opened this sheet for.
  var reveal: UUID? = nil
  var editsRevealed = false
  @Environment(\.dismiss) private var dismiss
  @State private var selected: UUID?
  @State private var draft: FavoriteDraft?
  @State private var confirmingGroupDelete = false
  @State private var importing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Favorites").font(.headline)
      Text("Drag a favorite onto a group to file it there. Changes save immediately.")
        .font(.caption)
      List(selection: $selected) {
        ForEach(settings.favorites) { node in
          switch node {
          case .item(let item):
            row(item).tag(item.id)
          case .group(let group):
            Section {
              ForEach(group.items) { item in
                HStack {
                  row(item)
                  Button("Move Out") { move(item.id, to: nil) }.buttonStyle(.borderless)
                }.tag(item.id)
              }
            } header: {
              Label(group.name, systemImage: "folder").tag(group.id)
                .contentShape(Rectangle())
                .onTapGesture { selected = group.id }
                .dropDestination(for: String.self) { ids, _ in
                  guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                  move(id, to: group.id)
                  return true
                }
            }
          }
        }
      }
      .frame(height: 300).accessibilityIdentifier("favoritesList")
      HStack {
        Button("New Favorite") { draft = FavoriteDraft(kind: .folder, folder: currentFolder) }
        Button("New Favorite Group") { draft = FavoriteDraft(kind: .group) }
        Button("Edit") { edit() }.disabled(selectedNode == nil)
        Button("Delete") { delete() }.disabled(selectedNode == nil)
        Button("Import…") { importing = true }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(20).frame(width: 560)
    .onAppear {
      selected = reveal
      if editsRevealed { edit() }
    }
    .sheet(item: $draft) { value in
      FavoriteEditor(draft: value, profiles: connections.profiles) { save($0) }
    }
    .sheet(isPresented: $importing) { FavoritesImportSheet(settings: settings) }
    .confirmationDialog(
      "Delete this group and the favorites in it?", isPresented: $confirmingGroupDelete
    ) {
      Button("Delete Group", role: .destructive) { remove() }
    }
  }

  private var currentFolder: String {
    guard let location = browser.activePane.location, location.providerID == "local" else {
      return ""
    }
    return location.path
  }

  private var selectedNode: FavoriteNode? {
    guard let selected else { return nil }
    return settings.favorites.first { $0.id == selected }
      ?? settings.favorites.item(selected).map { .item($0) }
  }

  private func row(_ item: FavoriteItem) -> some View {
    HStack {
      Label(item.name, systemImage: symbol(for: item))
      Spacer()
      Text(summary(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .draggable(item.id.uuidString)
  }

  private func symbol(for item: FavoriteItem) -> String {
    switch item.target {
    case .local(let path): path == FavoriteItem.iCloudDrivePath ? "icloud" : "folder"
    case .connection: "network"
    }
  }

  private func summary(_ item: FavoriteItem) -> String {
    switch item.target {
    case .local(let path): return path
    case .connection(let id, let paths):
      let name = connections.profiles.first { $0.id == id }?.displayName ?? "Missing connection"
      return paths.isEmpty ? name : "\(name) — \(paths.count) path\(paths.count == 1 ? "" : "s")"
    }
  }

  private func move(_ id: UUID, to group: UUID?) {
    settings.favorites = settings.favorites.moving(id, intoGroup: group)
  }

  private func edit() {
    guard let node = selectedNode else { return }
    switch node {
    case .group(let group):
      draft = FavoriteDraft(id: group.id, kind: .group, name: group.name, isNew: false)
    case .item(let item):
      switch item.target {
      case .local(let path):
        draft = FavoriteDraft(
          id: item.id, kind: .folder, name: item.name, folder: path, isNew: false)
      case .connection(let profileID, let paths):
        draft = FavoriteDraft(
          id: item.id, kind: .connection, name: item.name, profileID: profileID, paths: paths,
          isNew: false)
      }
    }
  }

  private func delete() {
    if case .group(let group) = selectedNode, !group.items.isEmpty {
      confirmingGroupDelete = true
    } else {
      remove()
    }
  }

  private func remove() {
    guard let selected else { return }
    settings.favorites = settings.favorites.removing(selected)
    self.selected = nil
  }

  private func save(_ draft: FavoriteDraft) {
    let node: FavoriteNode
    switch draft.kind {
    case .group:
      let items: [FavoriteItem]
      if case .group(let existing) = settings.favorites.first(where: { $0.id == draft.id }) {
        items = existing.items
      } else {
        items = []
      }
      node = .group(FavoriteGroup(id: draft.id, name: draft.name, items: items))
    case .folder:
      node = .item(
        FavoriteItem(id: draft.id, name: draft.name, target: .local(path: draft.folder)))
    case .connection:
      guard let profileID = draft.profileID else { return }
      node = .item(
        FavoriteItem(
          id: draft.id, name: draft.name,
          target: .connection(
            profileID: profileID,
            paths: draft.paths.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })))
    }
    settings.favorites =
      draft.isNew ? settings.favorites + [node] : settings.favorites.replacing(node)
  }
}

struct FavoriteDraft: Identifiable {
  enum Kind: String, CaseIterable {
    case folder = "Folder"
    case connection = "Connection"
    case group = "Group"
  }

  var id = UUID()
  var kind: Kind
  var name = ""
  var folder = ""
  var profileID: UUID?
  var paths: [String] = []
  var isNew = true
}

private struct FavoriteEditor: View {
  @State var draft: FavoriteDraft
  let profiles: [ConnectionProfile]
  let onSave: (FavoriteDraft) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(draft.kind == .group ? "Favorite Group" : "Favorite").font(.headline)
      TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("favoriteName")
      if draft.kind != .group {
        if draft.isNew {
          Picker("Kind", selection: $draft.kind) {
            Text("Folder").tag(FavoriteDraft.Kind.folder)
            Text("Connection").tag(FavoriteDraft.Kind.connection)
          }.pickerStyle(.segmented)
        }
        if draft.kind == .folder {
          TextField("Folder path", text: $draft.folder).textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("favoriteFolder")
          HStack {
            Button("Choose…") { chooseFolder() }
            Button("iCloud Drive") {
              draft.folder = FavoriteItem.iCloudDrivePath
              if draft.name.isEmpty { draft.name = "iCloud Drive" }
            }
          }
        } else {
          Picker("Connection", selection: $draft.profileID) {
            Text("Choose…").tag(UUID?.none)
            ForEach(profiles) { Text($0.displayName).tag(Optional($0.id)) }
          }
          Text(
            "Saved paths. Choosing one connects and opens it. With none, the connection's own folder opens."
          )
          .font(.caption)
          ForEach(draft.paths.indices, id: \.self) { index in
            HStack {
              TextField("Path", text: $draft.paths[index]).textFieldStyle(.roundedBorder)
              Button("Remove") { draft.paths.remove(at: index) }
            }
          }
          Button("Add Path") { draft.paths.append("/") }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          onSave(draft)
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(!isValid)
      }
    }.padding(20).frame(width: 480)
  }

  private var isValid: Bool {
    guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    switch draft.kind {
    case .group: return true
    case .folder: return draft.folder.hasPrefix("/")
    case .connection: return draft.profileID != nil
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    draft.folder = url.path
    if draft.name.isEmpty { draft.name = url.lastPathComponent }
  }
}
