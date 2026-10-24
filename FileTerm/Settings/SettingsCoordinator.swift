import AppKit
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
      Text("Settings for \(category.rawValue.lowercased()) will appear here.")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(28)
    .frame(width: 600, height: 280, alignment: .topLeading)
    .accessibilityIdentifier("settings.\(category.rawValue)")
    .onAppear { settings.selectedCategory = category.rawValue }
  }
}
