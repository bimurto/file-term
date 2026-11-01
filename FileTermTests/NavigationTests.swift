import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct NavigationTests {
  @Test func loweringTheRecentFolderLimitTrimsTheStoredList() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    settings.recentFolderLimit = 30
    for index in 0..<25 {
      settings.recordVisit(Location(providerID: "local", path: "/folder\(index)"))
    }
    #expect(settings.recentFolders.count == 25)
    settings.recentFolderLimit = 3
    #expect(settings.recentFolders == ["/folder24", "/folder23", "/folder22"])
    #expect(AppSettings(suite: suite).recentFolders == settings.recentFolders)
    settings.recentFolderLimit = 0
    #expect(settings.recentFolderLimit == 1)
    settings.recentFolderLimit = 500
    #expect(settings.recentFolderLimit == 50)
  }

  @Test func aListSavedWithTheOldLimitIsTrimmedAtLaunch() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    suite.set((0..<20).map { "/folder\($0)" }, forKey: "recentFolders")
    #expect(AppSettings(suite: suite).recentFolders.count == 10)
    #expect(suite.stringArray(forKey: "recentFolders")?.count == 10)
  }

  @Test func recentFoldersAreDeduplicatedCappedAndPersisted() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    for index in 0..<25 {
      settings.recordVisit(Location(providerID: "local", path: "/folder\(index)"))
    }
    settings.recordVisit(Location(providerID: "local", path: "/folder10"))
    settings.recordVisit(Location(providerID: "remote", path: "/ignored"))
    settings.toggle(.toolbar)
    let restored = AppSettings(suite: suite)
    #expect(restored.recentFolderLimit == 10)
    #expect(restored.recentFolders.count == 10)
    #expect(restored.recentFolders.first == "/folder10")
    #expect(Set(restored.recentFolders).count == 10)
    #expect(!restored.isVisible(.toolbar))
    #expect(restored.isVisible(.devices))
  }

  @Test func standardDestinationsUseExpectedDomains() throws {
    #expect(try StandardDestination.home.url() == FileManager.default.homeDirectoryForCurrentUser)
    #expect(
      try StandardDestination.library.url().path
        == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path)
    #expect(try StandardDestination.applications.url().path == "/Applications")
    #expect(try StandardDestination.utilities.url().path == "/Applications/Utilities")
    for destination in StandardDestination.allCases {
      #expect(try destination.url().path.hasPrefix("/"))
    }
  }

  @Test func goToFolderRejectsBadPathsAndResolvesLinks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Child"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("Link"),
      withDestinationURL: root.appendingPathComponent("Child"))
    try Data().write(to: root.appendingPathComponent("file"))
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let browser = BrowserModel(providers: [provider])
    await browser.navigate(to: provider.location(for: root), in: .first)
    let dialog = GoToFolderModel(browser: browser, provider: provider, paneID: .first)
    for invalid in [
      "relative", root.appendingPathComponent("missing").path,
      root.appendingPathComponent("file").path,
    ] {
      dialog.path = invalid
      #expect(await dialog.submit() == false)
      #expect(dialog.errorMessage != nil)
      #expect(browser.firstPane.location == provider.location(for: root))
    }
    dialog.path = root.appendingPathComponent("Link").path
    #expect(await dialog.submit())
    #expect(
      browser.firstPane.location?.path
        == root.appendingPathComponent("Child").resolvingSymlinksInPath().path)
  }

  @Test func goToFolderRemembersOnlyFoldersItReachedAndSuggestsThem() async throws {
    let name = "GoToFolderHistory-\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    for folder in ["Alpha", "Beta"] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = AppSettings(suite: suite)
    let provider = LocalFileSystemProvider()
    let browser = BrowserModel(providers: [provider])
    await browser.navigate(to: provider.location(for: root), in: .first)
    let dialog = GoToFolderModel(
      browser: browser, provider: provider, paneID: .first, settings: settings)
    let alpha = root.appendingPathComponent("Alpha").path
    let beta = root.appendingPathComponent("Beta").path

    dialog.path = root.appendingPathComponent("missing").path
    #expect(await dialog.submit() == false)
    #expect(settings.goToFolderHistory.isEmpty)

    dialog.path = alpha
    #expect(await dialog.submit())
    dialog.path = beta
    #expect(await dialog.submit())
    dialog.path = alpha
    #expect(await dialog.submit())
    #expect(settings.goToFolderHistory == [alpha, beta])
    #expect(AppSettings(suite: suite).goToFolderHistory == [alpha, beta])

    dialog.path = ""
    #expect(dialog.suggestions == [alpha, beta])
    dialog.path = alpha
    #expect(dialog.suggestions.isEmpty)
    dialog.path = "bEt"
    #expect(dialog.suggestions == [beta])
    dialog.path = root.path
    #expect(dialog.suggestions == [alpha, beta])
    dialog.path = "/no/such/prefix"
    #expect(dialog.suggestions.isEmpty)
  }

  @Test func goToFolderHistoryIsCappedAndPrefersPathsStartingWithWhatIsTyped() async throws {
    let name = "GoToFolderOrder-\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    for index in 0..<25 { settings.recordGoToFolder("/folder\(index)") }
    #expect(settings.goToFolderHistory.count == 20)
    #expect(settings.goToFolderHistory.first == "/folder24")
    settings.recordGoToFolder("/x/tmp")
    settings.recordGoToFolder("/tmp/x")
    let provider = LocalFileSystemProvider()
    let dialog = GoToFolderModel(
      browser: BrowserModel(providers: [provider]), provider: provider, paneID: .first,
      settings: settings)
    dialog.path = "/x"
    #expect(dialog.suggestions == ["/x/tmp", "/tmp/x"])
    dialog.path = "folder"
    #expect(dialog.suggestions.count == 6)
  }

  @Test func staleCapacityCannotReplaceTheCurrentLocation() async {
    let service = DelayedCapacityService()
    let status = PaneStatusModel()
    let old = Task {
      await status.update(for: Location(providerID: "local", path: "/old"), service: service)
    }
    await service.waitForRequest()
    await status.update(for: Location(providerID: "local", path: "/new"), service: service)
    #expect(status.availableBytes == 200)
    await service.finish()
    await old.value
    #expect(status.availableBytes == 200)
  }

  @Test func successfulEjectionRefreshesAndClearsSelection() async {
    let service = FakeVolumeService()
    await service.allowEjection()
    let devices = DeviceModel(service: service)
    await devices.refresh()
    devices.selectedVolumeID = "/Volumes/Test"
    await devices.ejectSelected()
    #expect(devices.volumes.isEmpty)
    #expect(devices.selectedVolumeID == nil)
    #expect(devices.errorMessage == nil)
  }

  @Test func deviceChangesAndFailedEjectionPreserveTheMountedVolume() async {
    let service = FakeVolumeService()
    let devices = DeviceModel(service: service)
    await devices.refresh()
    devices.selectedVolumeID = "/Volumes/Test"
    #expect(devices.canEject)
    await devices.ejectSelected()
    #expect(devices.volumes.count == 1)
    #expect(devices.errorMessage != nil)
    await service.removeVolumes()
    await devices.refresh()
    #expect(devices.volumes.isEmpty)
    #expect(devices.selectedVolumeID == nil)
    #expect(!devices.canEject)
  }
}

private actor FakeVolumeService: VolumeService {
  var mounted = [
    MountedVolume(
      url: URL(fileURLWithPath: "/Volumes/Test"), name: "Test", isEjectable: true,
      isInternal: false, isLocal: true, capacity: 100, available: 50)
  ]
  func volumes() -> [MountedVolume] { mounted }
  func availableCapacity(at location: Location) -> Int64? { 50 }
  private var allowsEjection = false
  func allowEjection() { allowsEjection = true }
  func eject(_ volume: MountedVolume) throws {
    if !allowsEjection { throw FileSystemError.io("Volume is busy.") }
    mounted = []
  }
  func removeVolumes() { mounted = [] }
}

private actor DelayedCapacityService: VolumeService {
  private var pending: CheckedContinuation<Int64?, Never>?
  func volumes() -> [MountedVolume] { [] }
  func availableCapacity(at location: Location) async -> Int64? {
    if location.path != "/old" { return 200 }
    return await withCheckedContinuation { pending = $0 }
  }
  func waitForRequest() async { while pending == nil { await Task.yield() } }
  func finish() {
    pending?.resume(returning: 100)
    pending = nil
  }
  func eject(_ volume: MountedVolume) throws { throw FileSystemError.unsupportedOperation }
}
