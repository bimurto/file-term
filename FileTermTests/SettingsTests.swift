import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct SettingsTests {
  @Test func persistsSettingsInAnIsolatedSuite() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let initial = AppSettings(suite: suite)
    #expect(initial.visiblePanels.isEmpty)
    #expect(initial.selectedCategory == "General")
    initial.toggle(.preview)
    initial.selectedCategory = "Themes"
    let restored = AppSettings(suite: suite)
    #expect(restored.isVisible(.preview))
    #expect(restored.selectedCategory == "Themes")
    #expect(SettingsCategory.allCases.count == 8)
  }

  @Test func persistsShowHiddenAutoRefreshSearchAndShortcuts() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let initial = AppSettings(suite: suite)
    #expect(!initial.showHidden)
    #expect(!initial.autoRefresh)
    #expect(initial.searchEngine == .builtIn)
    #expect(initial.searchIncludeSubfolders)
    #expect(initial.shortcutOverrides.isEmpty)
    initial.showHidden = true
    initial.autoRefresh = true
    initial.handleArchives = false
    initial.archivesAsFolders = true
    initial.detectAppOnDelete = false
    initial.compareTool = .vscode
    initial.searchEngine = .spotlight
    initial.searchIncludeSubfolders = false
    initial.shortcutOverrides["select.quick"] = ShortcutOverride(
      shortcut: Shortcut(key: "j", command: true))
    let restored = AppSettings(suite: suite)
    #expect(restored.showHidden)
    #expect(restored.viewPreferences.showHidden)
    #expect(restored.autoRefresh)
    #expect(restored.searchEngine == .spotlight)
    #expect(!restored.handleArchives)
    #expect(restored.archivesAsFolders)
    #expect(!restored.detectAppOnDelete)
    #expect(restored.compareTool == .vscode)
    let fresh = UserDefaults(suiteName: "com.fileterm.tests.\(UUID())")!
    #expect(AppSettings(suite: fresh).detectAppOnDelete)
    #expect(AppSettings(suite: fresh).compareTool == .fileMerge)
    #expect(!restored.searchIncludeSubfolders)
    #expect(restored.shortcutOverrides["select.quick"]?.shortcut?.display == "⌘J")
  }
}
