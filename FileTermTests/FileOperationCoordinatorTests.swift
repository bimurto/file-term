import AppKit
import FileTermCore
import Testing

@testable import FileTerm

@Suite(.serialized)
@MainActor struct FileOperationCoordinatorTests {
  @Test func localURLsIncludeOnlySelectedVisibleLocalEntries() async throws {
    let local = Location(providerID: "local", path: "/fixtures/selected.txt")
    let unselected = Location(providerID: "local", path: "/fixtures/unselected.txt")
    let remote = Location(providerID: "remote", path: "/fixtures/remote.txt")
    let stale = Location(providerID: "local", path: "/fixtures/not-in-listing.txt")
    let provider = CoordinatorListingProvider(entries: [
      FileEntry(location: local, name: "selected.txt", kind: .file),
      FileEntry(location: unselected, name: "unselected.txt", kind: .file),
      FileEntry(location: remote, name: "remote.txt", kind: .file),
    ])
    let pane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: Location(providerID: provider.id, path: "/fixtures")))
    pane.selection = [local, remote, stale]
    let coordinator = FileOperationCoordinator()

    #expect(Set(pane.selectedEntries.map(\.location)) == Set([local, remote]))
    #expect(coordinator.localURLs(pane) == [URL(fileURLWithPath: local.path)])
    pane.selection = [remote, stale]
    #expect(coordinator.localURLs(pane).isEmpty)
    pane.deselectAll()
    #expect(coordinator.localURLs(pane).isEmpty)
  }

  @Test func copyPublishesNativeFileURLsFromTheOriginatingPane() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let firstFolder = root.appendingPathComponent("First", isDirectory: true)
    let secondFolder = root.appendingPathComponent("Second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
    for name in ["selected one.txt", "selected-two.txt", "unselected.txt"] {
      try Data(name.utf8).write(to: firstFolder.appendingPathComponent(name))
    }
    try Data().write(to: secondFolder.appendingPathComponent("other.txt"))
    let provider = LocalFileSystemProvider()
    let first = PaneModel(providers: [provider])
    let second = PaneModel(providers: [provider])
    #expect(await first.navigate(to: provider.location(for: firstFolder)))
    #expect(await second.navigate(to: provider.location(for: secondFolder)))
    let firstSelection = Set(first.entries.filter { $0.name != "unselected.txt" }.map(\.location))
    let secondSelection = Set(second.entries.map(\.location))
    #expect(firstSelection.count == 2)
    #expect(secondSelection.count == 1)
    first.selection = firstSelection
    second.selection = secondSelection
    let coordinator = FileOperationCoordinator()
    let pasteboard = NSPasteboard.general
    let savedItems = try snapshot(pasteboard)
    var ownedRevision = pasteboard.changeCount
    defer { restore(savedItems, to: pasteboard, ifUnchangedSince: ownedRevision) }

    // Keep clipboard mutation and restoration synchronous: do not yield to another test here.
    coordinator.copy(first)
    ownedRevision = pasteboard.changeCount
    let nativeURLs =
      (pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    #expect(Set(nativeURLs.map(\.path)) == Set(firstSelection.map(\.path)))
    #expect(nativeURLs.allSatisfy { $0.isFileURL })
    #expect(pasteboard.pasteboardItems?.allSatisfy { $0.types.contains(.fileURL) } == true)
    #expect(Set(coordinator.clipboardURLs.map(\.path)) == Set(firstSelection.map(\.path)))

    coordinator.copy(second)
    ownedRevision = pasteboard.changeCount
    #expect(Set(coordinator.clipboardURLs.map(\.path)) == Set(secondSelection.map(\.path)))
    #expect(first.selection == firstSelection)
    #expect(second.selection == secondSelection)
    #expect(first.location == provider.location(for: firstFolder))
    #expect(second.location == provider.location(for: secondFolder))

    second.deselectAll()
    coordinator.copy(second)
    #expect(pasteboard.changeCount == ownedRevision)
    #expect(Set(coordinator.clipboardURLs.map(\.path)) == Set(secondSelection.map(\.path)))
  }

  @Test func clipboardURLsIgnorePlainTextAndNonFileURLs() throws {
    let pasteboard = NSPasteboard.general
    let savedItems = try snapshot(pasteboard)
    var ownedRevision = pasteboard.changeCount
    defer { restore(savedItems, to: pasteboard, ifUnchangedSince: ownedRevision) }
    let coordinator = FileOperationCoordinator()
    let text = NSPasteboardItem()
    text.setString("/not-a-native-file-url.txt", forType: .string)
    let web = NSPasteboardItem()
    web.setString("https://example.com/file.txt", forType: .URL)

    pasteboard.clearContents()
    ownedRevision = pasteboard.changeCount
    #expect(pasteboard.writeObjects([text, web]))
    ownedRevision = pasteboard.changeCount
    #expect(coordinator.clipboardURLs.isEmpty)
    coordinator.copy(PaneModel(providers: []))
    #expect(pasteboard.changeCount == ownedRevision)
    #expect(pasteboard.string(forType: .string) == "/not-a-native-file-url.txt")
  }

  @Test func startRenameSetsOnlyTheSingleSelectedPanesInlineState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appendingPathComponent("rename.txt"))
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    let otherPane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: provider.location(for: root)))
    #expect(await otherPane.navigate(to: provider.location(for: root)))
    let entry = try #require(pane.entries.first)
    pane.selection = [entry.location]
    let coordinator = FileOperationCoordinator()
    #expect(pane.onRename == nil)

    coordinator.startRename(pane, window: nil)

    #expect(pane.renamingLocation == entry.location)
    #expect(pane.onRename != nil)
    #expect(pane.selection == [entry.location])
    #expect(otherPane.renamingLocation == nil)
    #expect(otherPane.onRename == nil)
    #expect(!coordinator.isBusy)
    #expect(!coordinator.canUndo)
    #expect(!coordinator.canRedo)
    // Binding alone must not start an operation or present an extension-change alert.
    coordinator.bindRename(otherPane, window: nil)
    #expect(otherPane.onRename != nil)
    #expect(otherPane.renamingLocation == nil)
    #expect(!coordinator.isBusy)
  }

  @Test func queuedDuplicateAndHistoryUseFreshControls() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("sample.txt")
    try Data("contents".utf8).write(to: source)
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: provider.location(for: root)))
    pane.selection = [provider.location(for: source)]
    let coordinator = FileOperationCoordinator()
    coordinator.duplicate(pane, window: nil)
    #expect(coordinator.transfers.jobs.count == 1)
    for _ in 0..<400 {
      if !coordinator.isBusy { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let copied = root.appendingPathComponent("sample copy.txt")
    #expect(FileManager.default.fileExists(atPath: copied.path))
    #expect(coordinator.canUndo)
    #expect(coordinator.transfers.jobs.first?.summary.succeeded == 1)
    coordinator.history(redo: false, pane: pane, window: nil)
    for _ in 0..<400 {
      if !coordinator.isBusy { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!FileManager.default.fileExists(atPath: copied.path))
    #expect(coordinator.canRedo)
    #expect(coordinator.transfers.jobs.last?.canRetry == false)
    coordinator.history(redo: true, pane: pane, window: nil)
    for _ in 0..<400 {
      if !coordinator.isBusy { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(FileManager.default.fileExists(atPath: copied.path))
    #expect(coordinator.transfers.jobs.last?.state == .completed)
  }

  private func snapshot(_ pasteboard: NSPasteboard) throws -> [NSPasteboardItem] {
    try (pasteboard.pasteboardItems ?? []).map { original in
      let saved = NSPasteboardItem()
      for type in original.types {
        // Resolve promised representations before clearing their original owner.
        let data = try #require(original.data(forType: type))
        #expect(saved.setData(data, forType: type))
      }
      return saved
    }
  }

  private func restore(
    _ items: [NSPasteboardItem], to pasteboard: NSPasteboard, ifUnchangedSince revision: Int
  ) {
    // Never replace something the user (or another process) copied during the test.
    guard pasteboard.changeCount == revision else { return }
    pasteboard.clearContents()
    if !items.isEmpty { #expect(pasteboard.writeObjects(items)) }
  }
}

private struct CoordinatorListingProvider: FileSystemProvider {
  let id = "fixture"
  let entries: [FileEntry]
  func list(_ location: Location) async throws -> [FileEntry] { entries }
  func stat(_ location: Location) async throws -> FileEntry {
    throw FileSystemError.unsupportedOperation
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
  func delete(_ location: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }
}
