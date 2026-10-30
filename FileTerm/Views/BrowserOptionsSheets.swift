import FileTermCore
import SwiftUI

enum BrowserOptionsSheet: String, Identifiable {
  case viewOptions, toolbar, sidebar, favorites
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

struct ToolbarCustomizationSheet: View {
  @Bindable var settings: AppSettings
  let registry: CommandRegistry
  @Environment(\.dismiss) private var dismiss

  private var available: [AppCommand] {
    registry.commands.filter {
      $0.menuPath.count == 1 && ["File", "View", "Go", "Commands"].contains($0.menuPath[0])
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Customize Toolbar").font(.headline)
      Text("Choose registry commands and arrange the selected items. Changes save immediately.")
        .font(.caption)
      List {
        Section("Current Toolbar") {
          ForEach(settings.workspace.toolbarItems, id: \.self) { id in
            HStack {
              Label(registry.command(id)?.title ?? id, systemImage: ToolbarSymbols.symbol(for: id))
              Spacer()
              Button {
                move(id, by: -1)
              } label: {
                Image(systemName: "arrow.up")
              }.help("Move earlier")
              Button {
                move(id, by: 1)
              } label: {
                Image(systemName: "arrow.down")
              }.help("Move later")
              Button("Remove") { settings.workspace.toolbarItems.removeAll { $0 == id } }
            }
          }
        }
        Section("Available Commands") {
          ForEach(available.filter { !settings.workspace.toolbarItems.contains($0.id) }) {
            command in
            HStack {
              Text(command.title)
              Spacer()
              Button("Add") { settings.workspace.toolbarItems.append(command.id) }
            }
          }
        }
      }.frame(height: 320)
      HStack {
        Button("Restore Default Toolbar") {
          settings.workspace.toolbarItems = WorkspacePreferences().toolbarItems
        }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 520)
  }

  private func move(_ id: String, by step: Int) {
    guard let index = settings.workspace.toolbarItems.firstIndex(of: id),
      settings.workspace.toolbarItems.indices.contains(index + step)
    else { return }
    settings.workspace.toolbarItems.swapAt(index, index + step)
  }
}

struct SidebarEditorSheet: View {
  @Bindable var settings: AppSettings
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Sidebar Editor").font(.headline)
      Text("Choose visible sections and their order. Changes save immediately.").font(.caption)
      ForEach(settings.workspace.sidebarOrder, id: \.self) { section in
        let chrome: BrowserChrome = section == "devices" ? .devices : .recentFolders
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
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 420)
  }

  private func move(_ id: String, by step: Int) {
    guard let index = settings.workspace.sidebarOrder.firstIndex(of: id),
      settings.workspace.sidebarOrder.indices.contains(index + step)
    else { return }
    settings.workspace.sidebarOrder.swapAt(index, index + step)
  }
}
