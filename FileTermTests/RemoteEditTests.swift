import FileTermCore
import Foundation
import Testing

@testable import FileTerm

private actor EditRemote: FileSystemProvider {
  nonisolated let id = "sftp.edit"
  private var files: [String: Data] = [:]

  func text(_ path: String) -> String? { files[path].map { String(decoding: $0, as: UTF8.self) } }
  func seed(_ path: String, _ text: String) { files[path] = Data(text.utf8) }
  func paths() -> [String] { files.keys.sorted() }

  func list(_ location: Location) async throws -> [FileEntry] { [] }
  func stat(_ location: Location) async throws -> FileEntry {
    guard let data = files[location.path] else { throw FileSystemError.notFound }
    return FileEntry(
      location: location, name: (location.path as NSString).lastPathComponent, kind: .file,
      size: Int64(data.count))
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    guard let data = files[location.path] else { throw FileSystemError.notFound }
    return EditChunk(data: data)
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {
    guard files[location.path] == nil else { throw FileSystemError.destinationExists }
    var data = Data()
    while let chunk = try await contents.next() { data.append(chunk) }
    files[location.path] = data
  }
  func move(_ source: Location, to destination: Location) async throws {
    guard files[destination.path] == nil else { throw FileSystemError.destinationExists }
    files[destination.path] = files.removeValue(forKey: source.path)
  }
  func delete(_ location: Location) async throws { files[location.path] = nil }
  func createDirectory(_ location: Location) async throws {}
}

private final class EditChunk: FileByteReader, @unchecked Sendable {
  private var data: Data?
  init(data: Data) { self.data = data }
  func next() async throws -> Data? {
    defer { data = nil }
    return data
  }
}

@MainActor private final class Log {
  var confirmations: [String] = []
  var notices: [String] = []
  var opened: [URL] = []
}

@Suite(.serialized)
@MainActor struct RemoteEditTests {
  private let remotePath = "/docs/note.txt"

  private struct Rig {
    let remote: EditRemote
    let registry: ProviderRegistry
    let coordinator: FileOperationCoordinator
    let edits: RemoteEditCoordinator
    let log: Log
    let entry: FileEntry
  }

  private func rig(approve: Bool = true) async -> Rig {
    let remote = EditRemote()
    await remote.seed(remotePath, "v1")
    let registry = ProviderRegistry(providers: [LocalFileSystemProvider(), remote])
    let coordinator = FileOperationCoordinator()
    coordinator.registry = registry
    coordinator.describe = { $0.providerID == "local" ? $0.path : "Office: \($0.path)" }
    let log = Log()
    let edits = RemoteEditCoordinator(
      fileOperations: coordinator,
      confirm: { target, _ in
        log.confirmations.append(target)
        return approve
      },
      openFile: { file, _ in
        log.opened.append(file)
        return nil
      })
    let entry = FileEntry(
      location: Location(providerID: remote.id, path: remotePath), name: "note.txt",
      kind: .file, size: 2)
    return Rig(
      remote: remote, registry: registry, coordinator: coordinator, edits: edits, log: log,
      entry: entry)
  }

  private func settle(_ rig: Rig) async {
    for _ in 0..<500 {
      if !rig.coordinator.transfers.hasPendingWork { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  private func startEditing(_ rig: Rig) async throws -> RemoteEditCoordinator.Session {
    rig.edits.edit(rig.entry, editors: []) { rig.log.notices.append($0) }
    await settle(rig)
    return try #require(rig.edits.sessions.first)
  }

  @Test func theRemoteFileIsDownloadedAndOpenedButNothingIsUploadedYet() async throws {
    let rig = await rig()
    let session = try await startEditing(rig)
    #expect(try String(contentsOf: session.local, encoding: .utf8) == "v1")
    for _ in 0..<200 where rig.log.opened.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(rig.log.opened == [session.local])
    await rig.edits.check(session)  // nothing was saved
    #expect(rig.log.confirmations.isEmpty)
    #expect(await rig.remote.text(remotePath) == "v1")
  }

  @Test func theFirstSaveAsksOnceThenEverySaveUploadsAndIsLogged() async throws {
    let rig = await rig()
    let session = try await startEditing(rig)

    try Data("second version".utf8).write(to: session.local)
    await rig.edits.check(session)
    await settle(rig)
    #expect(rig.log.confirmations == ["Office: /docs/note.txt"])
    #expect(await rig.remote.text(remotePath) == "second version")
    #expect(
      rig.coordinator.transfers.logs.map(\.message).contains(
        "Uploaded note.txt to Office: /docs/note.txt"))

    try Data("a third, longer version".utf8).write(to: session.local)
    await rig.edits.check(session)
    await settle(rig)
    #expect(rig.log.confirmations.count == 1)
    #expect(await rig.remote.text(remotePath) == "a third, longer version")
    let jobs = rig.coordinator.transfers.jobs.filter { $0.kind == .upload }
    #expect(jobs.count == 2 && jobs.allSatisfy { $0.state == .completed })
    // The replace leaves no temporary file behind on the server.
    #expect(await rig.remote.paths() == [remotePath])
  }

  @Test func decliningStopsWatchingAndUploadsNothing() async throws {
    let rig = await rig(approve: false)
    let session = try await startEditing(rig)
    try Data("unwanted change".utf8).write(to: session.local)
    await rig.edits.check(session)
    await settle(rig)

    #expect(await rig.remote.text(remotePath) == "v1")
    #expect(rig.edits.sessions.isEmpty)
    #expect(rig.log.notices.last?.contains("not uploaded") == true)
    try Data("another unwanted change".utf8).write(to: session.local)
    await rig.edits.check(session)
    #expect(rig.log.confirmations.count == 1)
    #expect(!rig.coordinator.transfers.jobs.contains { $0.kind == .upload })
  }

  @Test func editingTheSameFileAgainReopensTheLocalCopy() async throws {
    let rig = await rig()
    let session = try await startEditing(rig)
    try Data("unsaved local work".utf8).write(to: session.local)
    rig.edits.edit(rig.entry, editors: []) { rig.log.notices.append($0) }
    await settle(rig)
    try await Task.sleep(for: .milliseconds(50))

    #expect(rig.edits.sessions.count == 1)
    #expect(rig.log.opened == [session.local, session.local])
    #expect(try String(contentsOf: session.local, encoding: .utf8) == "unsaved local work")
  }

  @Test func aClosedConnectionEndsTheSessionInsteadOfUploading() async throws {
    let rig = await rig()
    let session = try await startEditing(rig)
    rig.registry.unregister(id: rig.entry.location.providerID)
    try Data("edited after disconnect".utf8).write(to: session.local)
    await rig.edits.check(session)

    #expect(rig.edits.sessions.isEmpty)
    #expect(rig.log.confirmations.isEmpty)
    #expect(rig.log.notices.last?.contains("connection closed") == true)
  }

  @Test func anAtomicSaveOnDiskIsNoticedByTheWatcher() async throws {
    let rig = await rig()
    let session = try await startEditing(rig)
    // Editors often write a sibling file and rename it over the original.
    let sibling = session.local.deletingLastPathComponent().appendingPathComponent(".note.swp")
    try Data("saved by renaming".utf8).write(to: sibling)
    _ = try FileManager.default.replaceItemAt(session.local, withItemAt: sibling)

    var uploaded = false
    for _ in 0..<300 {
      if await rig.remote.text(remotePath) == "saved by renaming" {
        uploaded = true
        break
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(uploaded)
    #expect(rig.log.confirmations == ["Office: /docs/note.txt"])
  }
}
