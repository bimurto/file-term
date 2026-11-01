import FileTermCore
import Foundation
import Testing

@testable import FileTerm

private actor RemoteStub: FileSystemProvider {
  nonisolated let id = "webdav.stub"
  private var files: [String: Data] = [:]
  private var folders: Set<String> = ["/"]

  func text(_ path: String) -> String? { files[path].map { String(decoding: $0, as: UTF8.self) } }
  func seed(_ path: String, _ text: String) { files[path] = Data(text.utf8) }

  func list(_ location: Location) async throws -> [FileEntry] { [] }
  func stat(_ location: Location) async throws -> FileEntry {
    if folders.contains(location.path) {
      return FileEntry(location: location, name: "/", kind: .directory)
    }
    guard let data = files[location.path] else { throw FileSystemError.notFound }
    return FileEntry(
      location: location, name: (location.path as NSString).lastPathComponent, kind: .file,
      size: Int64(data.count))
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    guard let data = files[location.path] else { throw FileSystemError.notFound }
    return OneChunk(data: data)
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
  func createDirectory(_ location: Location) async throws { folders.insert(location.path) }
}

private final class OneChunk: FileByteReader, @unchecked Sendable {
  private var data: Data?
  init(data: Data) { self.data = data }
  func next() async throws -> Data? {
    defer { data = nil }
    return data
  }
}

@Suite(.serialized)
@MainActor struct ProviderCopyTests {
  @Test func downloadRefusesANameThatLeavesTheTemporaryFolder() async throws {
    let stub = RemoteStub()
    await stub.seed("/evil", "server bytes")
    let name = "escaped-\(UUID().uuidString).txt"
    let entry = FileEntry(
      location: Location(providerID: stub.id, path: "/evil"), name: "../" + name, kind: .file,
      size: 12)
    let escaped = FileOperationCoordinator.downloadsFolder.appendingPathComponent(name)
    defer { try? FileManager.default.removeItem(at: escaped) }

    await #expect(throws: FileSystemError.self) {
      _ = try await FileOperationCoordinator.download(
        entry, provider: stub, control: TransferControl())
    }
    #expect(!FileManager.default.fileExists(atPath: escaped.path))
  }

  private func waitForCompletion(_ coordinator: FileOperationCoordinator, _ id: UUID) async {
    for _ in 0..<400 {
      if coordinator.transfers.jobs.first(where: { $0.id == id })?.state.isTerminal == true {
        return
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test func directionAndReservationsFollowTheEndpoints() {
    let local = Location(providerID: "local", path: "/tmp/a")
    let remote = Location(providerID: "webdav.one", path: "/docs")
    let other = Location(providerID: "webdav.two", path: "/docs")
    #expect(FileOperationCoordinator.direction(from: [local], to: local) == .local)
    #expect(FileOperationCoordinator.direction(from: [remote], to: local) == .download)
    #expect(FileOperationCoordinator.direction(from: [local], to: remote) == .upload)
    #expect(FileOperationCoordinator.direction(from: [remote], to: other) == .relay)
    #expect(
      FileOperationCoordinator.resources(for: [remote, other, local])
        == ["remote:webdav.one", "remote:webdav.two", "/tmp"])
  }

  @Test func uploadsALocalFileThroughTheQueueAndLabelsTheJob() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("note.txt")
    try "hello".write(to: file, atomically: true, encoding: .utf8)
    let local = LocalFileSystemProvider()
    let remote = RemoteStub()
    let coordinator = FileOperationCoordinator()
    coordinator.registry = ProviderRegistry(providers: [local, remote])
    coordinator.describe = { $0.providerID == "local" ? $0.path : "Office: \($0.path)" }

    let id = try #require(
      coordinator.submitProviderCopy(
        sources: [local.location(for: file)], to: Location(providerID: remote.id, path: "/"),
        window: nil))
    await waitForCompletion(coordinator, id)

    let job = try #require(coordinator.transfers.jobs.first { $0.id == id })
    #expect(job.state == .completed)
    #expect(job.kind == .copy)
    #expect(job.destinationLabel == "Office: /")
    #expect(job.sourceLabels.first?.hasSuffix("note.txt") == true)
    #expect(job.summary.succeeded == 1)
    #expect(await remote.text("/note.txt") == "hello")
  }

  @Test func downloadsARemoteFileAndKeepsExistingFilesWithTheReplacePolicySkip() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try "keep me".write(
      to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let local = LocalFileSystemProvider()
    let remote = RemoteStub()
    await remote.seed("/a.txt", "from server")
    await remote.seed("/b.txt", "second")
    let coordinator = FileOperationCoordinator()
    coordinator.registry = ProviderRegistry(providers: [local, remote])
    var policy = TransferPreferences()
    policy.replacePolicy = .skip
    coordinator.preferences = { policy }

    let id = try #require(
      coordinator.submitProviderCopy(
        sources: [
          Location(providerID: remote.id, path: "/a.txt"),
          Location(providerID: remote.id, path: "/b.txt"),
        ], to: local.location(for: folder), window: nil))
    await waitForCompletion(coordinator, id)

    let job = try #require(coordinator.transfers.jobs.first { $0.id == id })
    #expect(job.state == .completed)
    #expect(job.summary.succeeded == 1 && job.summary.skipped == 1)
    #expect(
      try String(contentsOf: folder.appendingPathComponent("a.txt"), encoding: .utf8) == "keep me")
    #expect(
      try String(contentsOf: folder.appendingPathComponent("b.txt"), encoding: .utf8) == "second")
    #expect(coordinator.transfers.exportedLogs.contains("Conflict"))
  }
}
