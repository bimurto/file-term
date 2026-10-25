import Foundation
import Testing

@testable import FileTermCore

@MainActor struct MetadataIntegrationTests {
  @Test func calculatedSizesParticipateInSortingAndSelectionAndRefreshInvalidatesThem() async {
    let provider = MetadataFixtureProvider()
    let pane = PaneModel(providers: [provider])
    await pane.navigate(to: Location(providerID: provider.id, path: "/"))
    let folder = Location(providerID: provider.id, path: "/folder")
    pane.selection = [folder]
    pane.setCalculatedSize(42, for: folder)
    #expect(pane.selectedBytes == 42)
    #expect(!pane.hasUnknownSelectedSizes)
    #expect(pane.visibleEntries.first { $0.id == folder }?.size == 42)
    await pane.refresh()
    #expect(pane.hasUnknownSelectedSizes)
  }

  @Test func refreshRetainsNestedSearchSelectionAndUpdatesMetadata() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("needle.txt")
    try Data("a".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    await pane.navigate(to: provider.location(for: root))
    await pane.search(SearchQuery(text: "needle", includeSubfolders: true))
    pane.selectAll()
    try Data("updated".utf8).write(to: file)
    await pane.refresh()
    #expect(pane.selection == [provider.location(for: file)])
    #expect(pane.selectedBytes == 7)
  }

  @Test func localProviderHasNoPublicBaseURL() async throws {
    let provider = LocalFileSystemProvider()
    let url = try await provider.publicURL(for: Location(providerID: provider.id, path: "/"))
    #expect(url == nil)
  }
}

private actor MetadataFixtureProvider: FileSystemProvider {
  nonisolated let id = "metadata-fixture"
  func list(_ location: Location) async throws -> [FileEntry] {
    [
      FileEntry(
        location: Location(providerID: id, path: "/folder"), name: "folder", kind: .directory)
    ]
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
