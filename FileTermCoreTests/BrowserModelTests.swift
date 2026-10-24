import Foundation
import Testing

@testable import FileTermCore

@MainActor struct BrowserModelTests {
  private func location(_ path: String) -> Location { Location(providerID: "local", path: path) }

  @Test func changingLayoutCancelsAnInFlightMirror() async {
    let provider = NavigationProvider()
    let browser = BrowserModel(providers: [provider])
    await browser.navigate(to: location("/left"), in: .first)
    await browser.navigate(to: location("/right"), in: .second)
    browser.setLayout(.vertical)
    browser.syncBrowsing = true
    await provider.delay("/right/Child")
    let navigation = Task { await browser.enterFolder(location("/left/Child"), in: .first) }
    await provider.waitForRequest("/right/Child")
    browser.setLayout(.single)
    await provider.finish("/right/Child")
    await navigation.value
    #expect(browser.secondPane.location == location("/right"))
    #expect(!browser.secondPane.isLoading)
    #expect(!browser.syncBrowsing)
  }

  @Test func newerTargetVisitPreventsAnOlderSourceFromMirroring() async {
    let provider = NavigationProvider()
    let browser = BrowserModel(providers: [provider])
    await browser.navigate(to: location("/left"), in: .first)
    await browser.navigate(to: location("/right"), in: .second)
    browser.setLayout(.vertical)
    browser.syncBrowsing = true
    await provider.delay("/left/Child")
    let navigation = Task { await browser.enterFolder(location("/left/Child"), in: .first) }
    await provider.waitForRequest("/left/Child")
    await browser.navigate(to: location("/newer"), in: .second)
    await provider.finish("/left/Child")
    await navigation.value
    #expect(browser.secondPane.location == location("/newer"))
  }

  @Test func unmountRecoveryOnlyMovesPanesInsideThatVolume() async {
    let browser = BrowserModel(providers: [NavigationProvider()])
    await browser.navigate(to: location("/Volumes/Test/Child"), in: .first)
    await browser.navigate(to: location("/Volumes/Testing"), in: .second)
    await browser.handleUnmount(at: URL(fileURLWithPath: "/Volumes/Test"), home: location("/home"))
    #expect(browser.firstPane.location == location("/home"))
    #expect(browser.secondPane.location == location("/Volumes/Testing"))
    #expect(browser.notice != nil)
  }

  @Test func historyCommitsOnlySuccessfulNavigationAndBranches() async {
    let pane = PaneModel(providers: [NavigationProvider()])
    await pane.navigate(to: location("/a/child"))
    await pane.goUp()
    #expect(pane.location == location("/a"))
    await pane.goBack()
    #expect(pane.location == location("/a/child"))
    #expect(pane.canGoForward)
    await pane.navigate(to: location("/missing"))
    #expect(pane.canGoForward)
    await pane.navigate(to: location("/b"))
    #expect(!pane.canGoForward)
    await pane.navigate(to: location("/"))
    #expect(!pane.canGoUp)
  }

  @Test func layoutsKeepActivePaneAndSwapMovesWholeState() async {
    let browser = BrowserModel(providers: [NavigationProvider()])
    await browser.navigate(to: location("/left"), in: .first)
    await browser.navigate(to: location("/right"), in: .second)
    browser.setLayout(.vertical)
    browser.activePaneID = .second
    browser.setLayout(.single)
    #expect(browser.activePane.location == location("/right"))
    #expect(browser.targetPane == nil)
    browser.setLayout(.horizontal)
    browser.swapPanes()
    #expect(browser.activePane.location == location("/left"))
    #expect(browser.targetPane?.location == location("/right"))
    await browser.clonePane()
    #expect(browser.targetPane?.location == location("/left"))
    #expect(browser.targetPane?.canGoBack == true)
  }

  @Test func syncMirrorsEnterAndUpButNotDirectVisitsOrHistory() async {
    let browser = BrowserModel(providers: [NavigationProvider()])
    await browser.navigate(to: location("/left"), in: .first)
    await browser.navigate(to: location("/right"), in: .second)
    browser.setLayout(.vertical)
    browser.syncBrowsing = true
    await browser.enterFolder(location("/left/Child"), in: .first)
    #expect(browser.secondPane.location == location("/right/Child"))
    await browser.goUp(in: .first)
    #expect(browser.secondPane.location == location("/right"))
    await browser.goBack(in: .first)
    #expect(browser.secondPane.location == location("/right"))
    await browser.navigate(to: location("/other"), in: .first)
    #expect(browser.secondPane.location == location("/right"))
    browser.setLayout(.single)
    #expect(!browser.syncBrowsing)
  }

  @Test func missingSyncCounterpartPreservesTargetAndReportsFailure() async {
    let browser = BrowserModel(providers: [NavigationProvider()])
    await browser.navigate(to: location("/left"), in: .first)
    await browser.navigate(to: location("/right"), in: .second)
    browser.setLayout(.vertical)
    browser.syncBrowsing = true
    await browser.enterFolder(location("/left/OnlyLeft"), in: .first)
    #expect(browser.firstPane.location == location("/left/OnlyLeft"))
    #expect(browser.secondPane.location == location("/right"))
    #expect(browser.notice != nil)
  }
}

private actor NavigationProvider: FileSystemProvider {
  nonisolated let id = "local"
  private var delayed: Set<String> = []
  private var pending: [String: CheckedContinuation<[FileEntry], any Error>] = [:]
  func delay(_ path: String) { delayed.insert(path) }
  func waitForRequest(_ path: String) async { while pending[path] == nil { await Task.yield() } }
  func finish(_ path: String) { pending.removeValue(forKey: path)?.resume(returning: []) }
  func list(_ location: Location) async throws -> [FileEntry] {
    if delayed.contains(location.path) {
      return try await withCheckedThrowingContinuation { pending[location.path] = $0 }
    }
    if location.path == "/missing" || location.path == "/right/OnlyLeft" {
      throw FileSystemError.notFound
    }
    return []
  }
  func stat(_ location: Location) throws -> FileEntry { throw FileSystemError.unsupportedOperation }
  func read(_ location: Location) throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) throws {
    Issue.record("Navigation must never write files")
  }
  func move(_ source: Location, to destination: Location) throws {
    Issue.record("Navigation must never move files")
  }
  func delete(_ location: Location) throws { Issue.record("Navigation must never delete files") }
}
