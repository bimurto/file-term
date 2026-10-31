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

  @Test func savedWorkspacesPersistAndReplaceBySameName() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    let browser = BrowserModel(providers: [])
    let window = WindowSnapshot(browser: browser.snapshot(), frame: "{{0, 0}, {800, 600}}")
    settings.saveWorkspace(named: "Deploy", windows: [window])
    let id = try #require(settings.savedWorkspaces.first?.id)
    settings.saveWorkspace(named: "deploy", windows: [window, window])
    settings.saveWorkspace(named: "Photos", windows: [window])
    let restored = AppSettings(suite: suite).savedWorkspaces
    #expect(restored.map(\.name) == ["deploy", "Photos"])
    #expect(restored[0].id == id)
    #expect(restored[0].windows.count == 2)
  }

  @Test func sidebarSectionsAddNewerSectionsToAnOlderOrder() {
    var preferences = WorkspacePreferences()
    preferences.sidebarOrder = ["recents", "devices"]
    #expect(
      preferences.sidebarSections == [
        "recents", "devices", "tags", "iCloudDrive", "workspaces", "favorites",
      ])
    preferences.sidebarOrder = ["workspaces", "iCloudDrive", "tags", "devices", "recents"]
    #expect(
      preferences.sidebarSections == [
        "workspaces", "iCloudDrive", "tags", "devices", "recents", "favorites",
      ])
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
    settings.workspace.sidebarOrder = ["recents", "tags", "devices"]
    settings.viewPreferences.defaults.mode = .columns
    let location = Location(providerID: "local", path: "/tmp")
    var options = ViewOptions()
    options.sortField = .size
    settings.viewPreferences.folders[location] = options
    let restored = AppSettings(suite: suite)
    #expect(restored.workspace.restoreWindows)
    #expect(restored.workspace.startingDirectory == "/tmp")
    #expect(restored.workspace.toolbarItems == ["file.newTab", "view.asIcons"])
    #expect(restored.workspace.sidebarOrder == ["recents", "tags", "devices"])
    #expect(restored.viewPreferences.defaults.mode == .columns)
    #expect(restored.viewPreferences.folders[location]?.sortField == .size)
  }
}
