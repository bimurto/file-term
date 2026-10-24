import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct NavigationTests {
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
    #expect(restored.recentFolders.count == 20)
    #expect(restored.recentFolders.first == "/folder10")
    #expect(Set(restored.recentFolders).count == 20)
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
      isInternal: false, capacity: 100, available: 50)
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
