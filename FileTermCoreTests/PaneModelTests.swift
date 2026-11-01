import Foundation
import Testing

@testable import FileTermCore

@MainActor struct PaneModelTests {
  @Test func selectedSizeCountsKnownBytesAndReportsUnknowns() async {
    let model = PaneModel(providers: [FakeProvider()])
    await model.navigate(to: Location(providerID: "fake-connection", path: "root"))
    model.selection = Set(model.entries.map(\.id))
    #expect(model.selectedBytes == 10)
    #expect(model.selectedEntries.count == 3)
    #expect(model.hasUnknownSelectedSizes)
    model.selection = Set(model.entries.filter { $0.kind == .file }.map(\.id))
    #expect(model.selectedBytes == 10)
    #expect(!model.hasUnknownSelectedSizes)
  }

  @Test func refreshLeavesADeletedFolderForTheNearestParent() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let deep = root.appendingPathComponent("a/b/c")
    try fm.createDirectory(at: deep, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: deep.appendingPathComponent("gone.txt"))
    let provider = LocalFileSystemProvider()
    let model = PaneModel(providers: [provider])
    await model.navigate(to: provider.location(for: root))
    let start = try #require(model.location)
    await model.navigate(to: provider.location(for: deep))
    model.isPinned = true
    let parent = try #require(model.location?.parent?.parent)
    try fm.removeItem(at: root.appendingPathComponent("a/b"))
    #expect(await model.refresh())
    #expect(model.location == parent)
    #expect(model.entries.isEmpty)
    #expect(model.errorMessage == nil)
    #expect(model.movedNotice?.contains("“c” no longer exists") == true)
    #expect(!model.isLoading)
    #expect(!model.isPinned)
    // It survives the refreshes that follow, and goes when the user navigates.
    await model.refresh()
    #expect(model.movedNotice != nil)
    await model.navigate(to: start)
    #expect(model.movedNotice == nil)
  }

  @Test func aFolderClosedByItsModesOffersNoSystemSetting() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let closed = root.appendingPathComponent("closed")
    try fm.createDirectory(at: closed, withIntermediateDirectories: true)
    defer {
      try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: closed.path)
      try? fm.removeItem(at: root)
    }
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: closed.path)
    let provider = LocalFileSystemProvider()
    let model = PaneModel(providers: [provider])
    await model.navigate(to: provider.location(for: root))
    #expect(await !model.navigate(to: provider.location(for: closed)))
    #expect(model.deniedLocation == nil)
    #expect(model.errorMessage == FileSystemError.fileModesDenied.localizedDescription)
    model.dismissError()
    #expect(model.errorMessage == nil)
  }

  @Test func refreshStaysPutWhenAnotherErrorHidesTheFolder() async {
    let provider = FakeProvider()
    let model = PaneModel(providers: [provider])
    let root = Location(providerID: provider.id, path: "/data/changes")
    await model.navigate(to: root)
    await provider.setFailure(.permissionDenied)
    #expect(await !model.refresh())
    #expect(model.location == root)
    #expect(model.movedNotice == nil)
    #expect(model.errorMessage != nil)
  }

  @Test func browsesRemoteLocationsAndPreservesListingOnFailure() async {
    let provider = FakeProvider()
    let model = PaneModel(providers: [provider])
    let root = Location(providerID: provider.id, path: "bucket/prefix")
    await model.navigate(to: root)
    #expect(model.location == root)
    #expect(model.entries.map(\.name) == ["Folder", "a.txt", "z.txt"])
    model.selection = [model.entries[0].id]
    await model.navigate(to: Location(providerID: provider.id, path: "missing"))
    #expect(model.location == root)
    #expect(model.entries.count == 3)
    #expect(model.selection.count == 1)
    #expect(model.errorMessage != nil)
    #expect(!model.isLoading)
  }

  @Test func discardsOldNavigationResults() async {
    let provider = FakeProvider()
    let model = PaneModel(providers: [provider])
    let slow = Task { await model.navigate(to: Location(providerID: provider.id, path: "slow")) }
    await provider.waitForSlowRequest()
    let fast = Location(providerID: provider.id, path: "fast")
    await model.navigate(to: fast)
    await provider.finishSlowRequest()
    _ = await slow.value
    #expect(model.location == fast)
    #expect(!model.isLoading)
    #expect(model.errorMessage == nil)
  }
}

private actor FakeProvider: FileSystemProvider {
  nonisolated let id = "fake-connection"
  private var slowRequest: CheckedContinuation<[FileEntry], any Error>?
  private var failure: FileSystemError?

  func setFailure(_ error: FileSystemError) { failure = error }

  func list(_ location: Location) async throws -> [FileEntry] {
    if let failure { throw failure }
    if location.path == "missing" { throw FileSystemError.notFound }
    if location.path == "slow" {
      return try await withCheckedThrowingContinuation { slowRequest = $0 }
    }
    return [
      FileEntry(location: Location(providerID: id, path: "z"), name: "z.txt", kind: .file, size: 3),
      FileEntry(location: Location(providerID: id, path: "a"), name: "a.txt", kind: .file, size: 7),
      FileEntry(
        location: Location(providerID: id, path: "folder"), name: "Folder", kind: .directory),
    ]
  }

  func waitForSlowRequest() async {
    while slowRequest == nil { await Task.yield() }
  }

  func finishSlowRequest() {
    slowRequest?.resume(returning: [])
    slowRequest = nil
  }

  func stat(_ location: Location) throws -> FileEntry { throw FileSystemError.unsupportedOperation }
  func read(_ location: Location) throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) throws {
    throw FileSystemError.unsupportedOperation
  }
  func move(_ source: Location, to destination: Location) throws {
    throw FileSystemError.unsupportedOperation
  }
  func delete(_ location: Location) throws { throw FileSystemError.unsupportedOperation }
}
