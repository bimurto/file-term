import Foundation
import Testing

@testable import FileTermCore

@MainActor struct TabSessionTests {
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
