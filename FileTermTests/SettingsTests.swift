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
    #expect(SettingsCategory.allCases.count == 9)
  }

  @Test func persistsShowHiddenAutoRefreshSearchAndShortcuts() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let initial = AppSettings(suite: suite)
    #expect(!initial.showHidden)
    #expect(initial.autoRefresh)
    #expect(initial.searchEngine == .builtIn)
    #expect(initial.searchIncludeSubfolders)
    #expect(initial.shortcutOverrides.isEmpty)
    initial.showHidden = true
    initial.autoRefresh = false
    initial.handleArchives = false
    initial.archivesAsFolders = true
    initial.detectAppOnDelete = false
    initial.compareTool = .vscode
    initial.syncFavoritesToICloud = true
    let tool = UserTool(name: "Open", command: "open $SOURCE_SELECTION_PATHS", showInToolbar: true)
    initial.tools = [tool]
    let editor = EditorMapping(applicationPath: "/Applications/Zed.app", extensions: ["swift"])
    initial.editors = [editor]
    initial.terminalApplication = .iTerm
    let favorite = FavoriteItem(name: "Docs", target: .local(path: "/Users/me/Documents"))
    initial.favorites = [.group(FavoriteGroup(name: "Work", items: [favorite]))]
    initial.searchEngine = .spotlight
    initial.searchIncludeSubfolders = false
    initial.shortcutOverrides["select.quick"] = ShortcutOverride(
      shortcut: Shortcut(key: "j", command: true))
    let restored = AppSettings(suite: suite)
    #expect(restored.showHidden)
    #expect(restored.viewPreferences.showHidden)
    #expect(!restored.autoRefresh)
    #expect(restored.searchEngine == .spotlight)
    #expect(!restored.handleArchives)
    #expect(restored.archivesAsFolders)
    #expect(!restored.detectAppOnDelete)
    #expect(restored.compareTool == .vscode)
    #expect(restored.syncFavoritesToICloud)
    #expect(restored.tools == [tool])
    #expect(restored.editors == [editor])
    #expect(restored.terminalApplication == .iTerm)
    #expect(restored.favorites.allItems == [favorite])
    let fresh = UserDefaults(suiteName: "com.fileterm.tests.\(UUID())")!
    #expect(AppSettings(suite: fresh).detectAppOnDelete)
    #expect(AppSettings(suite: fresh).compareTool == .fileMerge)
    let seeded = AppSettings(suite: fresh)
    #expect(seeded.favorites.allItems.map(\.target) == FavoriteItem.defaults().map(\.target))
    // The defaults keep their IDs, and removing them all is not undone by the next launch.
    #expect(AppSettings(suite: fresh).favorites == seeded.favorites)
    seeded.favorites = []
    #expect(AppSettings(suite: fresh).favorites.isEmpty)
    #expect(!AppSettings(suite: fresh).syncFavoritesToICloud)
    #expect(AppSettings(suite: fresh).tools.isEmpty)
    #expect(AppSettings(suite: fresh).editors.isEmpty)
    #expect(AppSettings(suite: fresh).terminalApplication == .terminal)
    #expect(!restored.searchIncludeSubfolders)
    #expect(restored.shortcutOverrides["select.quick"]?.shortcut?.display == "⌘J")
  }
}

@MainActor struct AppearanceSettingsTests {
  private func isolated(_ body: (UserDefaults) throws -> Void) throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    try body(suite)
  }

  @Test func allBuiltInThemesShipAsValidDataFiles() throws {
    #expect(
      ThemeLibrary.themes.map(\.name) == [
        "Default", "Dark", "Light", "ForkLift", "Bluerange", "Dracula", "Commander", "Sand",
        "Polar Night",
      ])
    #expect(ThemeLibrary.themes[0].appearance == .system)
    #expect(ThemeLibrary.themes[1].appearance == .dark)
    #expect(ThemeLibrary.themes[2].appearance == .light)
    for theme in ThemeLibrary.themes {
      for color in [theme.accent, theme.background, theme.sidebar, theme.foreground] {
        if let color { #expect(AppTheme.components(hex: color) != nil, "\(theme.id): \(color)") }
      }
    }
  }

  @Test func newSettingsHaveTheirDefaultsAndPersist() throws {
    try isolated { suite in
      let initial = AppSettings(suite: suite)
      #expect(initial.theme.id == "default")
      #expect(initial.tags == FileTag.defaults)
      #expect(!initial.askBeforeDrag)
      #expect(!initial.automaticUpdateChecks)
      #expect(!initial.onboardingShown)
      #expect(initial.workspace.startingDirectory == NSHomeDirectory())
      #expect(!initial.workspace.restoreWindows)
      initial.themeID = "dracula"
      initial.tags = [FileTag(name: "Work", color: .blue)]
      initial.askBeforeDrag = true
      initial.automaticUpdateChecks = true
      initial.onboardingShown = true
      let restored = AppSettings(suite: suite)
      #expect(restored.theme.name == "Dracula")
      #expect(restored.tags == [FileTag(name: "Work", color: .blue)])
      #expect(restored.askBeforeDrag)
      #expect(restored.automaticUpdateChecks)
      #expect(restored.onboardingShown)
    }
  }

  @Test func removingEveryTagStaysRemoved() throws {
    try isolated { suite in
      AppSettings(suite: suite).tags = []
      #expect(AppSettings(suite: suite).tags.isEmpty)
    }
  }

  @Test func aSidebarSavedBeforeTagsGainsTheSection() throws {
    try isolated { suite in
      let settings = AppSettings(suite: suite)
      settings.workspace.sidebarOrder = ["recents", "devices"]
      #expect(AppSettings(suite: suite).workspace.sidebarOrder == ["recents", "devices", "tags"])
    }
  }

  @Test func onboardingShowsOnceAndNeverDuringTests() {
    #expect(OnboardingCoordinator.shouldShow(alreadyShown: false, environment: [:]))
    #expect(!OnboardingCoordinator.shouldShow(alreadyShown: true, environment: [:]))
    #expect(
      !OnboardingCoordinator.shouldShow(
        alreadyShown: false, environment: ["FILETERM_SETTINGS_SUITE": "x"]))
    #expect(
      !OnboardingCoordinator.shouldShow(
        alreadyShown: false, environment: ["XCTestConfigurationFilePath": "x"]))
    #expect(
      OnboardingCoordinator.shouldShow(
        alreadyShown: true,
        environment: ["FILETERM_SHOW_ONBOARDING": "1", "FILETERM_SETTINGS_SUITE": "x"]))
  }

  @Test func updateCheckerReportsEachOutcome() async throws {
    let url = try #require(URL(string: "https://example.com"))
    func checker(_ status: Int, _ body: String) -> UpdateChecker {
      UpdateChecker { _ in
        (
          Data(body.utf8),
          HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
      }
    }
    let json = #"{"tag_name":"v2.0.0","html_url":"https://example.com"}"#
    #expect(
      await checker(200, json).latest(current: "1.0.0")
        == .available(AppRelease(tag: "v2.0.0", page: url)))
    #expect(await checker(200, json).latest(current: "2.0.0") == .upToDate)
    #expect(await checker(404, "").latest(current: "1.0.0") == .noRelease)
    #expect(
      await checker(500, "").latest(current: "1.0.0")
        == .failed("The update server returned 500."))
    if case .failed = await checker(200, "nope").latest(current: "1.0.0") {
    } else {
      Issue.record("A malformed response should fail")
    }
  }

  @Test func theBundleCarriesAVersionAndBuildForAbout() {
    #expect(UpdateChecker.currentVersion == "0.1.0")
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1")
  }
}
