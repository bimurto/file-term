import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct WorkspaceSettingsTests {
  @Test func defaultToolbarHasTheFavoritesButton() {
    #expect(WorkspacePreferences().toolbarItems.contains("go.favorites.manage"))
    #expect(ToolbarSymbols.symbol(for: "go.favorites.manage") == "star")
  }

  @Test func defaultToolbarHasTheOpenInTerminalButton() {
    #expect(WorkspacePreferences().toolbarItems.contains("file.openInTerminal"))
    #expect(ToolbarSymbols.symbol(for: "file.openInTerminal") == "apple.terminal")
  }

  @Test func defaultToolbarHasTheDeleteButton() {
    #expect(WorkspacePreferences().toolbarItems.contains("file.trash"))
    #expect(ToolbarSymbols.symbol(for: "file.trash") == "trash")
  }

  @Test func customizationViewPreferencesAndSessionSettingsPersist() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    #expect(!settings.workspace.restoreWindows)
    settings.workspace.restoreWindows = true
    settings.workspace.startingDirectory = "/tmp"
    settings.workspace.toolbarItems = ["file.newTab", "view.asIcons"]
    settings.workspace.sidebarOrder = ["recents", "devices"]
    settings.viewPreferences.defaults.mode = .columns
    let location = Location(providerID: "local", path: "/tmp")
    var options = ViewOptions()
    options.sortField = .size
    settings.viewPreferences.folders[location] = options
    let restored = AppSettings(suite: suite)
    #expect(restored.workspace.restoreWindows)
    #expect(restored.workspace.startingDirectory == "/tmp")
    #expect(restored.workspace.toolbarItems == ["file.newTab", "view.asIcons"])
    #expect(restored.workspace.sidebarOrder == ["recents", "devices"])
    #expect(restored.viewPreferences.defaults.mode == .columns)
    #expect(restored.viewPreferences.folders[location]?.sortField == .size)
  }
}
