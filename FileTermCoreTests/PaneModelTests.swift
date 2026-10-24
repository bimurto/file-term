import Foundation
import Testing

@testable import FileTermCore

@MainActor struct PaneModelTests {
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

  func list(_ location: Location) async throws -> [FileEntry] {
    if location.path == "missing" { throw FileSystemError.notFound }
    if location.path == "slow" {
      return try await withCheckedThrowingContinuation { slowRequest = $0 }
    }
    return [
      FileEntry(location: Location(providerID: id, path: "z"), name: "z.txt", kind: .file),
      FileEntry(location: Location(providerID: id, path: "a"), name: "a.txt", kind: .file),
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
