import Foundation
import Testing

@testable import FileTermCore

@MainActor @Suite struct ProviderRegistryTests {
  @Test func severalConnectionsBrowseInDifferentPanesAndTabs() async throws {
    let registry = ProviderRegistry(providers: [ListingProvider(id: "local")])
    let one = ListingProvider(id: "webdav.one")
    let two = ListingProvider(id: "webdav.two")
    registry.register(one)
    registry.register(two)
    let browser = BrowserModel(registry: registry)
    browser.setLayout(.vertical)
    #expect(await browser.navigate(to: Location(providerID: one.id, path: "/"), in: .first))
    #expect(await browser.navigate(to: Location(providerID: two.id, path: "/"), in: .second))
    browser.newTab(in: .first)
    #expect(
      await browser.navigate(to: Location(providerID: two.id, path: "/"), in: .first))
    #expect(browser.firstTabs.tabs.map { $0.location?.providerID } == [one.id, two.id])
    #expect(browser.secondPane.entries.first?.location.providerID == two.id)
  }

  @Test func unregisteringOnlyAffectsThatConnection() async throws {
    let registry = ProviderRegistry()
    let one = ListingProvider(id: "webdav.one")
    let two = ListingProvider(id: "webdav.two")
    registry.register(one)
    registry.register(two)
    let pane = PaneModel(registry: registry)
    registry.unregister(id: one.id)
    #expect(!(await pane.navigate(to: Location(providerID: one.id, path: "/"))))
    #expect(pane.errorMessage != nil)
    #expect(await pane.navigate(to: Location(providerID: two.id, path: "/")))
  }

  @Test func duplicatedTabsShareTheRegistry() async throws {
    let registry = ProviderRegistry()
    let pane = PaneModel(registry: registry)
    let copy = pane.duplicate()
    let late = ListingProvider(id: "webdav.late")
    registry.register(late)
    #expect(await copy.navigate(to: Location(providerID: late.id, path: "/")))
  }

  @Test func disconnectMovesTabsToHome() async throws {
    let local = ListingProvider(id: "local")
    let remote = ListingProvider(id: "webdav.one")
    let registry = ProviderRegistry(providers: [local, remote])
    let browser = BrowserModel(registry: registry)
    let home = Location(providerID: "local", path: "/home")
    await browser.navigate(to: Location(providerID: remote.id, path: "/"), in: .first)
    registry.unregister(id: remote.id)
    await browser.handleDisconnect(providerID: remote.id, home: home)
    #expect(browser.firstPane.location == home)
    #expect(browser.notice != nil)
  }
}

private actor ListingProvider: FileSystemProvider {
  nonisolated let id: String
  init(id: String) { self.id = id }
  func list(_ location: Location) async throws -> [FileEntry] {
    [
      FileEntry(
        location: Location(providerID: id, path: "/item"), name: "item", kind: .file, size: 1)
    ]
  }
  func stat(_ location: Location) async throws -> FileEntry {
    FileEntry(location: location, name: "item", kind: .file)
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }
  func move(_ source: Location, to destination: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }
  func delete(_ location: Location) async throws { throw FileSystemError.unsupportedOperation }
}
