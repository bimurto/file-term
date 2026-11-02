import FileTermCore
import SwiftUI

enum BrowserOptionsSheet: String, Identifiable {
  case viewOptions, sidebar, favorites, favoritesImport
  var id: String { rawValue }
}

struct ViewOptionsSheet: View {
  let pane: PaneModel
  @Environment(\.dismiss) private var dismiss
  @State private var options: ViewOptions
  @State private var scope: ViewSettingsScope

  init(pane: PaneModel) {
    self.pane = pane
    _options = State(initialValue: pane.viewOptions)
    _scope = State(initialValue: pane.viewScope)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("View Options").font(.headline)
      Picker("Apply to", selection: $scope) {
        ForEach(ViewSettingsScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.accessibilityIdentifier("viewOptionsScope")
      Text(
        scope == .tab
          ? "Applies to this tab across folders."
          : "Saved for this folder, shared by tabs using This Folder scope."
      )
      .font(.caption).foregroundStyle(.secondary)
      if scope == .folder {
        Text(pane.location?.path ?? "No folder open").font(.caption).textSelection(.enabled)
      }
      Picker("View", selection: $options.mode) {
        ForEach(FileViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Picker("Sort by", selection: $options.sortField) {
        ForEach(FileSortField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Toggle("Descending Order", isOn: $options.descending)
      Picker("Group by", selection: $options.groupField) {
        ForEach(FileGroupField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      Toggle("Show File Size in Icon View", isOn: $options.showsIconSize)
        .accessibilityIdentifier("viewOptionsIconSize")
      HStack {
        Button("Save View Settings as Defaults") { pane.viewPreferences.defaults = options }
        Button("Restore Defaults") { options = pane.viewPreferences.defaults }
      }
      Text("Defaults apply to new tabs and folders without saved settings.").font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Apply") {
          pane.viewScope = scope
          pane.viewOptions = options
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(scope == .folder && pane.location == nil)
      }
    }.padding(20).frame(width: 490)
  }
}

/// Names a single sidebar row for `AppSettings.hiddenSidebarItems`.
enum SidebarItemKey {
  static func volume(_ volume: MountedVolume) -> String { "volume:" + volume.url.path }
  static func favorite(_ item: FavoriteItem) -> String { "favorite:" + item.id.uuidString }

  static func title(of key: String, favorites: [FavoriteNode]) -> String {
    if key.hasPrefix("volume:") {
      let path = String(key.dropFirst("volume:".count))
      return URL(fileURLWithPath: path).lastPathComponent
    }
    let id = UUID(uuidString: String(key.dropFirst("favorite:".count)))
    return id.flatMap { favorites.item($0)?.name } ?? key
  }
}

struct SidebarEditorSheet: View {
  @Bindable var settings: AppSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Sidebar Editor").font(.headline)
      Text("Choose visible sections and their order. Changes save immediately.").font(.caption)
      ForEach(settings.workspace.sidebarSections, id: \.self) { section in
        let chrome = BrowserChrome.forSidebarSection(section)
        HStack {
          Toggle(
            chrome.title,
            isOn: Binding(
              get: { settings.isVisible(chrome) },
              set: { value in if value != settings.isVisible(chrome) { settings.toggle(chrome) } }))
          Spacer()
          Button {
            move(section, by: -1)
          } label: {
            Image(systemName: "arrow.up")
          }.help("Move earlier")
          Button {
            move(section, by: 1)
          } label: {
            Image(systemName: "arrow.down")
          }.help("Move later")
        }
      }
      if !settings.hiddenSidebarItems.isEmpty {
        Text("Hidden Items").font(.subheadline)
        ForEach(settings.hiddenSidebarItems.sorted(), id: \.self) { key in
          HStack {
            Text(SidebarItemKey.title(of: key, favorites: settings.favorites)).lineLimit(1)
            Spacer()
            Button("Show") { settings.hiddenSidebarItems.remove(key) }
              .accessibilityIdentifier("showSidebarItem.\(key)")
          }
        }
      }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 420)
  }

  private func move(_ id: String, by step: Int) {
    var order = settings.workspace.sidebarSections
    guard let index = order.firstIndex(of: id), order.indices.contains(index + step) else { return }
    order.swapAt(index, index + step)
    settings.workspace.sidebarOrder = order
  }
}
