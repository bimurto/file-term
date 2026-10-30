import AppKit
import FileTermCore
import Testing

@testable import FileTerm

/// Runs inside the app, so the menus and windows here are the real ones.
@Suite(.serialized)
@MainActor struct MacIntegrationTests {
  private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
  }

  private func titles(_ menu: String) async throws -> [String] {
    #expect(await eventually { NSApp.mainMenu?.item(withTitle: menu) != nil })
    let submenu = try #require(NSApp.mainMenu?.item(withTitle: menu)?.submenu)
    submenu.delegate?.menuNeedsUpdate?(submenu)
    return submenu.items.map(\.title)
  }

  @Test func theAppMenuOffersUpdatesAndServices() async throws {
    // Twice, because the menu is rebuilt each time it opens.
    for _ in 0..<2 {
      let items = try await titles("FileTerm")
      #expect(items.contains("About FileTerm"))
      #expect(items.contains("Check for Updates…"))
      #expect(items.filter { $0 == "Services" }.count == 1)
    }
    let services = NSApp.mainMenu?.item(withTitle: "FileTerm")?.submenu?.item(withTitle: "Services")
    #expect(services?.submenu === NSApp.servicesMenu)
  }

  @Test func rebuildingTheEditMenuKeepsItemsAppKitAdded() async throws {
    let before = try await titles("Edit")
    #expect(before.contains("Select All"))
    let edit = try #require(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
    edit.addItem(withTitle: "System Item", action: nil, keyEquivalent: "")
    defer { edit.removeItem(at: edit.numberOfItems - 1) }
    #expect(try await titles("Edit").contains("System Item"))
  }

  @Test func theEditMenuHasEachSystemItemOnce() async throws {
    #expect(await eventually { NSApp.mainMenu?.item(withTitle: "Edit") != nil })
    let edit = try #require(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
    edit.update()
    let items = try await titles("Edit").filter { !$0.isEmpty }
    #expect(items.contains("Emoji & Symbols"))
    #expect(items.contains { $0.contains("Dictation") })
    #expect(items.contains("AutoFill"))
    #expect(Set(items).count == items.count, "\(items)")
  }

  @Test func aBrowserWindowOffersTheSelectedLocalFilesToServices() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("a file.txt")
    try Data("a".utf8).write(to: file)

    let provider = LocalFileSystemProvider()
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    let providers = ProviderRegistry(providers: [provider])
    let browser = BrowserModel(registry: providers, viewPreferences: settings.viewPreferences)
    let controller = BrowserWindowController(
      browser: browser, devices: DeviceModel(service: NativeVolumeService()), settings: settings,
      registry: CommandRegistry(
        commands: [],
        context: { CommandContext(hasBrowserWindow: true, hasKeyWindow: true, isLoading: false) }),
      provider: provider,
      connections: ConnectionCoordinator(settings: settings, registry: providers))
    defer { controller.window.close() }
    await browser.navigate(to: provider.location(for: root), in: .first)
    browser.activePaneID = .first

    let window = controller.window
    #expect(window.validRequestor(forSendType: .fileURL, returnType: nil) as? NSWindow !== window)
    browser.activePane.selection = [provider.location(for: file)]
    #expect(window.validRequestor(forSendType: .fileURL, returnType: nil) as? NSWindow === window)
    #expect(
      window.validRequestor(forSendType: .fileURL, returnType: .string) as? NSWindow !== window)

    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let requestor = try #require(window as? NSServicesMenuRequestor)
    #expect(requestor.writeSelection?(to: pasteboard, types: [.fileURL]) == true)
    let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    #expect(urls?.map(\.lastPathComponent) == ["a file.txt"])
  }

  private func dropFixture() throws -> (root: URL, file: URL, target: URL, pane: PaneModel) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let target = root.appendingPathComponent("Target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("sample.txt")
    try Data("sample".utf8).write(to: file)
    return (root, file, target, PaneModel(providers: [LocalFileSystemProvider()]))
  }

  @Test func aDropMovesOnTheSameVolume() async throws {
    let fixture = try dropFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    #expect(
      await fixture.pane.navigate(to: Location(providerID: "local", path: fixture.target.path)))
    let manager = FileManager.default
    await FileOperationCoordinator().drop(
      [fixture.file], onto: fixture.pane, confirm: false, optionPressed: false, window: nil)
    let moved = fixture.target.appendingPathComponent("sample.txt")
    #expect(await eventually { manager.fileExists(atPath: moved.path) })
    #expect(await eventually { !manager.fileExists(atPath: fixture.file.path) })
  }

  @Test func holdingOptionMakesADropCopy() async throws {
    let fixture = try dropFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    #expect(
      await fixture.pane.navigate(to: Location(providerID: "local", path: fixture.target.path)))
    await FileOperationCoordinator().drop(
      [fixture.file], onto: fixture.pane, confirm: false, optionPressed: true, window: nil)
    let copied = fixture.target.appendingPathComponent("sample.txt")
    #expect(await eventually { FileManager.default.fileExists(atPath: copied.path) })
    #expect(FileManager.default.fileExists(atPath: fixture.file.path))
  }

  @Test func droppingAFolderOnItselfDoesNothing() async throws {
    let fixture = try dropFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    #expect(
      await fixture.pane.navigate(to: Location(providerID: "local", path: fixture.target.path)))
    let coordinator = FileOperationCoordinator()
    await coordinator.drop(
      [fixture.target], onto: fixture.pane, confirm: false, optionPressed: false, window: nil)
    #expect(coordinator.transfers.jobs.isEmpty)
    #expect(FileManager.default.fileExists(atPath: fixture.target.path))
  }
}
