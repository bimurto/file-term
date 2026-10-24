import Foundation
import Testing

@testable import FileTermCore

@MainActor struct TabSessionTests {
  @Test func newTabsUseSavedDefaultsAndPinnedForksKeepTheirView() async {
    let provider = LocalFileSystemProvider()
    let preferences = ViewPreferences()
    preferences.defaults.sortField = .size
    let browser = BrowserModel(providers: [provider], viewPreferences: preferences)
    await browser.navigate(
      to: provider.location(for: FileManager.default.temporaryDirectory), in: .first)
    browser.firstPane.viewOptions.mode = .icons
    browser.firstPane.viewOptions.sortField = .name
    browser.newTab(in: .first)
    #expect(browser.firstPane.viewOptions.mode == .list)
    #expect(browser.firstPane.viewOptions.sortField == .size)
    browser.firstPane.viewOptions.mode = .columns
    browser.firstPane.isPinned = true
    await browser.navigate(to: Location(providerID: "local", path: "/"), in: .first)
    #expect(browser.firstPane.viewOptions.mode == .columns)
  }

  @Test func tabsKeepIndependentHistoriesAndPinnedNavigationOpensANewTab() async {
    let provider = LocalFileSystemProvider()
    let browser = BrowserModel(providers: [provider])
    let root = provider.location(for: FileManager.default.temporaryDirectory)
    await browser.navigate(to: root, in: .first)
    let original = browser.firstPane
    browser.newTab(in: .first)
    await browser.navigate(to: Location(providerID: "local", path: "/"), in: .first)
    #expect(browser.firstTabs.tabs.count == 2)
    #expect(original.location == root)
    browser.selectTab(original.id, in: .first)
    #expect(browser.firstPane === original)
    #expect(!original.canGoBack)
    original.isPinned = true
    await browser.navigate(to: Location(providerID: "local", path: "/"), in: .first)
    #expect(browser.firstTabs.tabs.count == 3)
    #expect(original.location == root)
    #expect(original.isPinned)
    #expect(!browser.firstPane.isPinned)
    browser.closeOtherTabs(in: .first)
    #expect(browser.firstTabs.tabs.count == 1)
    #expect(!browser.closeTab(in: .first))
  }

  @Test func sessionsRoundTripLocationsLayoutsTabsHistoryAndViewOptions() async throws {
    let provider = LocalFileSystemProvider()
    let browser = BrowserModel(providers: [provider])
    let root = provider.location(for: FileManager.default.temporaryDirectory)
    await browser.navigate(to: root, in: .first)
    await browser.navigate(to: Location(providerID: "local", path: "/"), in: .first)
    await browser.navigate(to: root, in: .second)
    browser.newTab(in: .second)
    browser.secondPane.viewOptions.mode = .icons
    browser.secondPane.isPinned = true
    browser.setLayout(.horizontal)
    browser.activePaneID = .second
    let data = try JSONEncoder().encode(browser.snapshot())
    let restored = BrowserModel(providers: [provider])
    await restored.restore(
      try JSONDecoder().decode(BrowserSnapshot.self, from: data), fallback: root)
    #expect(restored.layout == .horizontal)
    #expect(restored.activePaneID == .second)
    #expect(restored.secondTabs.tabs.count == 2)
    #expect(restored.secondPane.viewOptions.mode == .icons)
    #expect(restored.secondPane.isPinned)
    #expect(restored.firstPane.canGoBack)
    await restored.goBack(in: .first)
    #expect(restored.firstPane.location == root)
  }
}
