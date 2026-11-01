import Foundation
import Testing

@testable import FileTermCore

struct LocalFileOperationsTests {
  private func sandbox() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func createValidatesNamesAndUsesUniqueNames() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = LocalFileOperations()
    for name in ["", ".", "..", "a/b", "a\0b"] {
      await #expect(throws: (any Error).self) {
        try await engine.create(in: root, name: name, directory: false)
      }
    }
    let file = try await engine.create(in: root, name: "hello", directory: false)
    try Data("original".utf8).write(to: file)
    let second = try await engine.create(in: root, name: "hello", directory: false)
    #expect(second != file)
    #expect(try String(contentsOf: file, encoding: .utf8) == "original")
  }

  @Test func permanentDeleteRemovesItemsAndLeavesNothingToUndo() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("gone.txt")
    let folder = root.appendingPathComponent("folder")
    try Data("x".utf8).write(to: file)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("y".utf8).write(to: folder.appendingPathComponent("inner.txt"))
    let engine = LocalFileOperations()
    try await engine.deletePermanently(sources: [file, folder])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    #expect(await !engine.hasUndoHistory())
    await #expect(throws: (any Error).self) { try await engine.deletePermanently(sources: [file]) }
  }

  #if os(macOS)
    @Test func trashRestoresOriginalLocationAndRedoes() async throws {
      let root = try sandbox()
      defer { try? FileManager.default.removeItem(at: root) }
      let source = root.appendingPathComponent("trash-test-\(UUID().uuidString)")
      try Data("recover me".utf8).write(to: source)
      let engine = LocalFileOperations()
      let trashed = try await engine.trash(sources: [source])
      #expect(!FileManager.default.fileExists(atPath: source.path))
      #expect(trashed.count == 1)
      try await engine.undo()
      #expect(try String(contentsOf: source, encoding: .utf8) == "recover me")
      try await engine.redo()
      #expect(!FileManager.default.fileExists(atPath: source.path))
      try await engine.undo()
    }
  #endif

  #if os(macOS)
    @Test func undoingACopyUsesTheTrashAndRedoBringsItBack() async throws {
      let root = try sandbox()
      defer { try? FileManager.default.removeItem(at: root) }
      let source = root.appendingPathComponent("trash-copy-\(UUID().uuidString).txt")
      try Data("copy me".utf8).write(to: source)
      let engine = LocalFileOperations()
      let copy = try #require(try await engine.duplicate(sources: [source]).first)
      try await engine.undo()
      #expect(!FileManager.default.fileExists(atPath: copy.path))
      try await engine.redo()
      #expect(try String(contentsOf: copy, encoding: .utf8) == "copy me")
    }
  #endif

  @Test func copiesLeaveNoRecoveryFolderBehind() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("note.txt")
    try Data("text".utf8).write(to: source)
    let target = root.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let engine = LocalFileOperations.withFakeTrash()
    func recoveryFolders(in folder: URL) throws -> [String] {
      try FileManager.default.contentsOfDirectory(atPath: folder.path)
        .filter { $0.hasPrefix(".FileTerm-recovery-") }
    }
    _ = try await engine.duplicate(sources: [source])
    _ = try await engine.transfer(sources: [source], to: target, move: false)
    #expect(try recoveryFolders(in: root).isEmpty)
    #expect(try recoveryFolders(in: target).isEmpty)
    try await engine.undo()
    try await engine.undo()
    #expect(try recoveryFolders(in: root).isEmpty)
    #expect(try recoveryFolders(in: target).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    try await engine.redo()
    try await engine.redo()
    #expect(
      try String(contentsOf: target.appendingPathComponent("note.txt"), encoding: .utf8) == "text")
    #expect(try recoveryFolders(in: target).isEmpty)
  }

  @Test func undoOfACopyKeepsTheCopyWhenItCannotBeTrashed() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("note.txt")
    try Data("text".utf8).write(to: source)
    let engine = LocalFileOperations(trash: { _ in throw CocoaError(.featureUnsupported) })
    let copy = try #require(try await engine.duplicate(sources: [source]).first)
    await #expect(throws: CocoaError(.featureUnsupported)) { try await engine.undo() }
    #expect(FileManager.default.fileExists(atPath: copy.path))
    #expect(await engine.historyState().canUndo)
  }

  private func replaceFixture() throws -> (root: URL, source: URL, target: URL, old: URL) {
    let root = try sandbox()
    let source = root.appendingPathComponent("a.txt")
    let target = root.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try Data(repeating: 7, count: 300_000).write(to: source)
    let old = target.appendingPathComponent("a.txt")
    try Data("old".utf8).write(to: old)
    return (root, source, target, old)
  }

  private let replaceIt: ConflictResolver = { _ in ConflictResolution(decision: .replace) }

  @Test func aReplacedItemGoesToTheTrashAndUndoBringsItBack() async throws {
    let f = try replaceFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let engine = LocalFileOperations.withFakeTrash()
    _ = try await engine.transfer(
      sources: [f.source], to: f.target, move: false, resolve: replaceIt)
    #expect(try Data(contentsOf: f.old).count == 300_000)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.target.path) == ["a.txt"])
    try await engine.undo()
    #expect(try String(contentsOf: f.old, encoding: .utf8) == "old")
  }

  @Test func cancellingAReplacePutsTheOldVersionBack() async throws {
    let f = try replaceFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let engine = LocalFileOperations.withFakeTrash()
    let relay = ReplaceCancelRelay()
    let control = TransferControl(progress: { _ in await relay.cancel() })
    await relay.set(control)
    await engine.setTransferControl(control)
    await #expect(throws: CancellationError.self) {
      try await engine.transfer(
        sources: [f.source], to: f.target, move: false, resolve: replaceIt)
    }
    #expect(try String(contentsOf: f.old, encoding: .utf8) == "old")
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.target.path) == ["a.txt"])
    #expect(await !engine.hasUndoHistory())
  }

  @Test(arguments: [false, true]) func aFailedReplacePutsTheOldVersionBack(move: Bool) async throws
  {
    let f = try replaceFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let engine = LocalFileOperations(
      rename: { source, destination in
        if destination.lastPathComponent == "a.txt", !source.path.contains("fake-trash") {
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        }
        try LocalFileOperations.exclusiveRename(source, destination)
      },
      remove: { try FileManager.default.removeItem(at: $0) },
      trash: LocalFileOperations.fakeTrash)
    await #expect(throws: (any Error).self) {
      try await engine.transfer(sources: [f.source], to: f.target, move: move, resolve: replaceIt)
    }
    #expect(try String(contentsOf: f.old, encoding: .utf8) == "old")
    #expect(FileManager.default.fileExists(atPath: f.source.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.target.path) == ["a.txt"])
  }

  @Test func withNoTrashAReplacedItemStaysBesideItAndUndoWorks() async throws {
    let f = try replaceFixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let engine = LocalFileOperations(trash: { _ in throw CocoaError(.featureUnsupported) })
    _ = try await engine.transfer(sources: [f.source], to: f.target, move: true, resolve: replaceIt)
    let names = try FileManager.default.contentsOfDirectory(atPath: f.target.path)
    #expect(names.contains { $0.hasPrefix(".FileTerm-recovery-") })
    try await engine.undo()
    #expect(try String(contentsOf: f.old, encoding: .utf8) == "old")
    #expect(FileManager.default.fileExists(atPath: f.source.path))
  }

  @Test func crossDeviceUndoRemovalFailureRetainsCopiesAndCanRetry() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("new")
    let engine = LocalFileOperations(
      rename: { source, destination in
        if source == file { throw NSError(domain: NSPOSIXErrorDomain, code: 18) }
        try LocalFileOperations.exclusiveRename(source, destination)
      },
      remove: { source in
        if source == file { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: source)
      })
    _ = try await engine.create(in: root, name: "new", directory: false)
    await #expect(throws: (any Error).self) { try await engine.undo() }
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(await engine.historyState().canUndo)
    // A second attempt reaches the same deletion failure, not destinationExists.
    await #expect(throws: CocoaError(.fileWriteNoPermission)) { try await engine.undo() }
    #expect(await engine.historyState().canUndo)
  }

  @Test func multiChunkContentEditsBlockUndoAndRenameNeverOverwrites() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("large")
    var payload = Data(repeating: 17, count: 3 * 1_048_576 + 23)
    try payload.write(to: source)
    let occupied = root.appendingPathComponent("occupied")
    try Data("keep".utf8).write(to: occupied)
    #expect(throws: (any Error).self) {
      try LocalFileOperations.exclusiveRename(source, occupied)
    }
    let engine = LocalFileOperations()
    await #expect(throws: (any Error).self) {
      try await engine.rename(source: source, name: "occupied")
    }
    #expect(try String(contentsOf: occupied, encoding: .utf8) == "keep")
    let copy = try #require(try await engine.duplicate(sources: [source]).first)
    let modified = try FileManager.default.attributesOfItem(atPath: copy.path)[.modificationDate]
    payload[payload.count - 1] = 99
    try payload.write(to: copy)
    if let modified {
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: copy.path)
    }
    await #expect(throws: (any Error).self) { try await engine.undo() }
    #expect(try Data(contentsOf: copy) == payload)
  }

  @Test func sameNameRenameIsANoopAndErrorsAreReadable() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    try Data("data".utf8).write(to: source)
    let engine = LocalFileOperations()
    #expect(try await engine.rename(source: source, name: "file") == source)
    #expect(!(await engine.historyState().canUndo))
    #expect(LocalFileOperationError.invalidName.errorDescription?.contains("name") == true)
  }

  @Test func folderWithSelectionIsOneUndoableUnit() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("selected")
    try Data("data".utf8).write(to: source)
    let engine = LocalFileOperations()
    let folder = try await engine.createWithSelection(in: root, name: "Folder", sources: [source])
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("selected").path))
    try await engine.undo()
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(!(await engine.historyState().canUndo))
    try await engine.redo()
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("selected").path))
  }

  @Test func createUndoRedoAndChangedContentGuard() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = LocalFileOperations()
    let file = try await engine.create(in: root, name: "new", directory: false)
    try await engine.undo()
    #expect(!FileManager.default.fileExists(atPath: file.path))
    try await engine.redo()
    try Data("user edit".utf8).write(to: file)
    await #expect(throws: (any Error).self) { try await engine.undo() }
    #expect(try String(contentsOf: file, encoding: .utf8) == "user edit")
    let history = await engine.historyState()
    #expect(!history.canUndo)
    #expect(history.undoReason != nil)
  }

  @Test func replacementRestoresBothVersionsAndRedoRefusesOccupiedTarget() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try Data("new".utf8).write(to: source)
    let destination = target.appendingPathComponent("source")
    try Data("old".utf8).write(to: destination)
    let engine = LocalFileOperations.withFakeTrash()
    _ = try await engine.transfer(sources: [source], to: target, move: false) { _ in
      ConflictResolution(decision: .replace)
    }
    #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    try await engine.undo()
    #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
    try await engine.redo()
    #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    try await engine.undo()
    try Data("external change".utf8).write(to: destination)
    await #expect(throws: (any Error).self) { try await engine.redo() }
    #expect(try String(contentsOf: destination, encoding: .utf8) == "external change")
  }

  @Test func duplicateUniqueNamesAndRenameAreReversible() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("note.txt")
    try Data("text".utf8).write(to: source)
    let engine = LocalFileOperations.withFakeTrash()
    let copies = try await engine.duplicate(sources: [source, source])
    #expect(Set(copies).count == 2)
    #expect(copies.allSatisfy { $0.pathExtension == "txt" && $0 != source })
    let renamed = try await engine.rename(source: copies[0], name: "renamed.txt")
    try await engine.undo()
    #expect(!FileManager.default.fileExists(atPath: renamed.path))
    #expect(FileManager.default.fileExists(atPath: copies[0].path))
    try await engine.undo()
    #expect(copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
  }

  @Test func rejectsSelfDescendantsAndSymlinkedParents() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder")
    let nested = folder.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: nested)
    let engine = LocalFileOperations()
    for target in [root, nested, alias] {
      await #expect(throws: (any Error).self) {
        try await engine.transfer(sources: [folder], to: target, move: false)
      }
    }
  }

  @Test func mergeApplyAllStillResolvesChildrenAndUndoPreservesExistingFolder() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("folder")
    let target = root.appendingPathComponent("target")
    let destination = target.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: source.appendingPathComponent("a"))
    try Data("old".utf8).write(to: destination.appendingPathComponent("a"))
    let calls = ConflictCalls()
    let engine = LocalFileOperations.withFakeTrash()
    _ = try await engine.transfer(sources: [source], to: target, move: true) { conflict in
      await calls.record()
      return ConflictResolution(
        decision: conflict.isDirectoryMerge ? .merge : .replace, applyToAll: true)
    }
    #expect(await calls.count == 2)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    try await engine.undo()
    #expect(try String(contentsOf: source.appendingPathComponent("a"), encoding: .utf8) == "new")
    #expect(
      try String(contentsOf: destination.appendingPathComponent("a"), encoding: .utf8) == "old")
    try await engine.redo()
    #expect(!FileManager.default.fileExists(atPath: source.path))
  }

  @Test func movesAndDanglingSymlinkCopiesUndoWithoutFollowingLinks() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try Data("payload".utf8).write(to: source)
    let engine = LocalFileOperations.withFakeTrash()
    let moved = try await engine.transfer(sources: [source], to: target, move: true)
    #expect(!FileManager.default.fileExists(atPath: source.path))
    try await engine.undo()
    #expect(try String(contentsOf: source, encoding: .utf8) == "payload")
    try await engine.redo()
    try Data("edited".utf8).write(to: moved[0])
    await #expect(throws: (any Error).self) { try await engine.undo() }
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing")
    let copies = try await engine.duplicate(sources: [link])
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copies[0].path) == "missing")
    try await engine.undo()
    #expect((try? FileManager.default.attributesOfItem(atPath: copies[0].path)) == nil)
    try await engine.redo()
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copies[0].path) == "missing")
  }

  @Test func partialFailureRetainsUndoableCompletedWork() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data("payload".utf8).write(to: source)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let engine = LocalFileOperations()
    await #expect(throws: (any Error).self) {
      try await engine.transfer(
        sources: [source, root.appendingPathComponent("missing")], to: target, move: false)
    }
    #expect(await engine.historyState().canUndo)
    try await engine.undo()
    #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("source").path))
  }

  @Test func skipKeepBothStopAndReplaceOlder() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    let target = root.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try Data("new".utf8).write(to: source)
    let destination = target.appendingPathComponent("file")
    try Data("old".utf8).write(to: destination)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: source.path)
    let engine = LocalFileOperations()
    for decision in [ConflictDecision.skip, .replaceOlder, .stop] {
      let result = try await engine.transfer(sources: [source], to: target, move: false) { _ in
        ConflictResolution(decision: decision)
      }
      #expect(result.isEmpty)
    }
    let result = try await engine.transfer(sources: [source], to: target, move: false) { _ in
      ConflictResolution(decision: .keepBoth)
    }
    #expect(result.count == 1 && result[0] != destination)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "old")
  }
}

private actor ConflictCalls {
  var count = 0
  func record() { count += 1 }
}

private actor ReplaceCancelRelay {
  private var control: TransferControl?
  func set(_ control: TransferControl) { self.control = control }
  func cancel() async { await control?.cancel() }
}

extension LocalFileOperations {
  /// Stands in for the Trash, so tests don't fill the real one.
  @Sendable static func fakeTrash(_ url: URL) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FileTerm-fake-trash-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let destination = folder.appendingPathComponent(url.lastPathComponent)
    try exclusiveRename(url, destination)
    return destination
  }

  static func withFakeTrash() -> LocalFileOperations { LocalFileOperations(trash: fakeTrash) }
}
