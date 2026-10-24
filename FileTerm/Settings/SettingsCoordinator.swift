import AppKit
import FileTermCore
import Settings
import SwiftUI

@MainActor final class SettingsCoordinator {
  private let settings: AppSettings
  private lazy var controller = SettingsWindowController(
    panes: SettingsCategory.allCases.map { category in
      Settings.Pane(
        identifier: Settings.PaneIdentifier(category.rawValue),
        title: category.rawValue,
        toolbarIcon: NSImage(
          systemSymbolName: category.symbol, accessibilityDescription: category.rawValue)!
      ) {
        SettingsCategoryView(category: category, settings: self.settings)
      }
    },
    animated: false
  )

  init(settings: AppSettings) { self.settings = settings }

  func show() {
    let category = SettingsCategory(rawValue: settings.selectedCategory) ?? .general
    controller.show(pane: Settings.PaneIdentifier(category.rawValue))
  }
}

private struct SettingsCategoryView: View {
  let category: SettingsCategory
  let settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(category.rawValue).font(.title2).fontWeight(.semibold)
      if category == .general {
        GeneralSettingsView(settings: settings)
      } else {
        Text("Settings for \(category.rawValue.lowercased()) will appear here.").foregroundStyle(
          .secondary)
      }
      Spacer()
    }
    .padding(28)
    .frame(width: 600, height: 320, alignment: .topLeading)
    .accessibilityIdentifier("settings.\(category.rawValue)")
    .onAppear { settings.selectedCategory = category.rawValue }
  }
}

private struct GeneralSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var directory = ""
  @State private var error: String?
  @State private var isSaving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle("Restore windows and tabs on startup", isOn: $settings.workspace.restoreWindows)
        .accessibilityIdentifier("restoreSession")
      Text("Starting Directory").font(.headline)
      TextField("Absolute folder path", text: $directory).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("startingDirectory")
        .onSubmit { saveDirectory() }
      HStack {
        Button("Set Starting Directory") { saveDirectory() }.disabled(isSaving)
        Text("Used by new windows and when session restoration is off.").font(.caption)
          .foregroundStyle(.secondary)
      }
      Text("Current: " + settings.workspace.startingDirectory).font(.caption).foregroundStyle(
        .secondary)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }.onAppear { directory = settings.workspace.startingDirectory }
  }

  private func saveDirectory() {
    guard !isSaving else { return }
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        let location = try await LocalFileSystemProvider().resolveFolderPath(directory)
        settings.workspace.startingDirectory = location.path
        directory = location.path
        error = nil
      } catch { self.error = error.localizedDescription }
    }
  }
}
