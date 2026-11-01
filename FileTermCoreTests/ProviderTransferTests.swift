import Foundation
import Testing

@testable import FileTermCore

@Suite struct ProviderTransferTests {
  private func engine(
    _ providers: [any FileSystemProvider], verification: CopyVerification = .none,
    control: TransferControl = TransferControl(),
    resolve: @escaping LocationConflictResolver = { _ in ConflictResolution(decision: .skip) }
  ) -> ProviderTransfer {
    ProviderTransfer(
      registry: ProviderRegistry(providers: providers), control: control,
      verification: verification, resolve: resolve)
  }

  private func at(_ provider: MemoryProvider, _ path: String) -> Location {
    Location(providerID: provider.id, path: path)
  }

  private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: Copying

  @Test func copiesBetweenLocalAndMemoryBothWays() async throws {
    let local = LocalFileSystemProvider()
    let memory = MemoryProvider(id: "mem")
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("tree/sub"), withIntermediateDirectories: true)
    try "hello world".write(
      to: folder.appendingPathComponent("tree/a.txt"), atomically: true, encoding: .utf8)
    try "nested".write(
      to: folder.appendingPathComponent("tree/sub/b.txt"), atomically: true, encoding: .utf8)

    let up = engine([local, memory])
    let summary = try await up.copy(
      sources: [local.location(for: folder.appendingPathComponent("tree"))], to: at(memory, "/"))
    #expect(await memory.text("/tree/a.txt") == "hello world")
    #expect(await memory.text("/tree/sub/b.txt") == "nested")
    #expect(summary.succeeded == 4 && summary.failed == 0)

    let target = folder.appendingPathComponent("down")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let down = engine([local, memory])
    _ = try await down.copy(sources: [at(memory, "/tree")], to: local.location(for: target))
    #expect(
      try String(contentsOf: target.appendingPathComponent("tree/sub/b.txt"), encoding: .utf8)
        == "nested")
  }

  @Test func copiesBetweenTwoRemotesWithANewName() async throws {
    let first = MemoryProvider(id: "one")
    let second = MemoryProvider(id: "two")
    await first.seedFile("/report.txt", "quarterly")
    let transfer = engine([first, second])
    _ = try await transfer.copy(
      sources: [at(first, "/report.txt")], to: at(second, "/"), newName: "renamed.txt")
    #expect(await second.text("/renamed.txt") == "quarterly")
    #expect(await first.text("/report.txt") == "quarterly")
  }

  @Test func neverShowsTemporaryNamesAfterSuccessOrFailure() async throws {
    let first = MemoryProvider(id: "one")
    let second = MemoryProvider(id: "two")
    await first.seedFile("/good.txt", "abcdefghij")
    await first.seedFile("/bad.txt", "abcdefghij")
    _ = try await engine([first, second]).copy(
      sources: [at(first, "/good.txt")], to: at(second, "/"))
    #expect(await second.paths().filter { $0.contains(".part") }.isEmpty)

    await second.configure(failWritesAfterChunks: 1)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine([first, second]).copy(
        sources: [self.at(first, "/bad.txt")], to: self.at(second, "/other"))
    }
    #expect(await second.paths().filter { $0.contains(".part") }.isEmpty)
    #expect(await second.text("/bad.txt") == nil)
  }

  @Test func skipsLinksAndRejectsCopyingAFolderIntoItself() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedDirectory("/dir")
    await memory.seedFile("/dir/a.txt", "a")
    await memory.seedLink("/dir/link")
    await memory.seedDirectory("/dest")
    let summary = try await engine([memory]).copy(
      sources: [at(memory, "/dir")], to: at(memory, "/dest"))
    #expect(summary.skipped == 1 && summary.succeeded == 2)
    #expect(await memory.text("/dest/dir/link") == nil)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine([memory]).copy(
        sources: [self.at(memory, "/dir")], to: self.at(memory, "/dir/inner"))
    }
  }

  // MARK: Replacing

  @Test func aFailedFileReplaceKeepsTheOldVersion() async throws {
    let source = MemoryProvider(id: "src")
    await source.seedFile("/a.txt", "new")
    let destination = MemoryProvider(id: "dst")
    await destination.seedFile("/a.txt", "old")
    await destination.configure(failWritesAfterChunks: 1)
    await #expect(throws: (any Error).self) {
      try await engine(
        [source, destination], resolve: { _ in ConflictResolution(decision: .replace) }
      ).copy(sources: [at(source, "/a.txt")], to: at(destination, "/"))
    }
    #expect(await destination.text("/a.txt") == "old")
    #expect(await destination.paths() == ["/", "/a.txt"])
  }

  @Test func aReplaceThatFailsToLandPutsTheOldVersionBack() async throws {
    let source = MemoryProvider(id: "src")
    await source.seedFile("/a.txt", "new")
    let destination = MemoryProvider(id: "dst")
    await destination.seedFile("/a.txt", "old")
    await destination.failMoves(onto: "/a.txt")
    let failure = await #expect(throws: (any Error).self) {
      try await engine(
        [source, destination], resolve: { _ in ConflictResolution(decision: .replace) }
      ).copy(sources: [at(source, "/a.txt")], to: at(destination, "/"))
    }
    // Putting it back hits the same failing move, so the error must say where it is.
    #expect(failure?.localizedDescription.contains("The old version is still at") == true)
    let kept = await destination.paths().filter { $0.hasSuffix(".old") }
    #expect(kept.count == 1)
    #expect(await destination.text(kept[0]) == "old")
  }

  @Test func aFailedFolderReplaceKeepsTheOldFolder() async throws {
    let source = MemoryProvider(id: "src")
    await source.seedDirectory("/d")
    await source.seedFile("/d/new.txt", "new")
    let destination = MemoryProvider(id: "dst")
    await destination.seedDirectory("/d")
    await destination.seedFile("/d/old.txt", "old")
    await destination.configure(failWritesAfterChunks: 1)
    await #expect(throws: (any Error).self) {
      try await engine(
        [source, destination], resolve: { _ in ConflictResolution(decision: .replace) }
      ).copy(sources: [at(source, "/d")], to: at(destination, "/"))
    }
    #expect(await destination.text("/d/old.txt") == "old")
    #expect(await destination.paths() == ["/", "/d", "/d/old.txt"])
  }

  @Test func aSuccessfulFolderReplaceLeavesOnlyTheNewFolder() async throws {
    let source = MemoryProvider(id: "src")
    await source.seedDirectory("/d")
    await source.seedFile("/d/new.txt", "new")
    let destination = MemoryProvider(id: "dst")
    await destination.seedDirectory("/d")
    await destination.seedFile("/d/old.txt", "old")
    _ = try await engine(
      [source, destination], resolve: { _ in ConflictResolution(decision: .replace) }
    ).copy(sources: [at(source, "/d")], to: at(destination, "/"))
    #expect(await destination.paths() == ["/", "/d", "/d/new.txt"])
  }

  @Test func anItemCanNotReplaceItself() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedDirectory("/docs")
    await memory.seedFile("/docs/a.txt", "alpha")
    await #expect(throws: (any Error).self) {
      try await engine([memory], resolve: { _ in ConflictResolution(decision: .replace) })
        .copy(sources: [at(memory, "/docs/a.txt")], to: at(memory, "/docs/"))
    }
    #expect(await memory.text("/docs/a.txt") == "alpha")
  }

  // MARK: Conflicts

  @Test func conflictDecisionsAreHonouredAndNeverOverwriteSilently() async throws {
    let source = MemoryProvider(id: "src")
    await source.seedFile("/a.txt", "new", modified: Date(timeIntervalSince1970: 2000))
    for (decision, expected, extra) in [
      (ConflictDecision.skip, "old", nil),
      (.replace, "new", nil),
      (.keepBoth, "old", "new"),
      (.replaceOlder, "new", nil),
    ] as [(ConflictDecision, String, String?)] {
      let destination = MemoryProvider(id: "dst")
      await destination.seedFile("/a.txt", "old", modified: Date(timeIntervalSince1970: 1000))
      _ = try await engine(
        [source, destination], resolve: { _ in ConflictResolution(decision: decision) }
      ).copy(sources: [at(source, "/a.txt")], to: at(destination, "/"))
      #expect(await destination.text("/a.txt") == expected, "\(decision)")
      #expect(await destination.text("/a 2.txt") == extra, "\(decision)")
    }
    let stopped = MemoryProvider(id: "dst")
    await stopped.seedFile("/a.txt", "old")
    await stopped.seedFile("/b.txt", "old")
    await source.seedFile("/b.txt", "new")
    let summary = try await engine(
      [source, stopped], resolve: { _ in ConflictResolution(decision: .stop) }
    ).copy(
      sources: [at(source, "/a.txt"), at(source, "/b.txt")], to: at(stopped, "/"))
    #expect(summary.succeeded == 0)
    #expect(await stopped.text("/b.txt") == "old")
  }

  @Test func askingIsRememberedWhenApplyToAllIsChosen() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    for name in ["a", "b", "c"] {
      await source.seedFile("/\(name).txt", "new")
      await destination.seedFile("/\(name).txt", "old")
    }
    let asked = Counter()
    _ = try await engine(
      [source, destination],
      resolve: { _ in
        await asked.increment()
        return ConflictResolution(decision: .skip, applyToAll: true)
      }
    ).copy(
      sources: ["a", "b", "c"].map { at(source, "/\($0).txt") }, to: at(destination, "/"))
    #expect(await asked.value == 1)
  }

  @Test func replaceKeepsTheOriginalWhenTheUploadFails() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/a.txt", "brand new content")
    await destination.seedFile("/a.txt", "precious")
    await destination.configure(failWritesAfterChunks: 1)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine(
        [source, destination], resolve: { _ in ConflictResolution(decision: .replace) }
      ).copy(sources: [self.at(source, "/a.txt")], to: self.at(destination, "/"))
    }
    #expect(await destination.text("/a.txt") == "precious")
  }

  @Test func foldersMergeWithoutTouchingOtherItems() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedDirectory("/docs")
    await source.seedFile("/docs/new.txt", "new")
    await destination.seedDirectory("/docs")
    await destination.seedFile("/docs/keep.txt", "keep")
    _ = try await engine(
      [source, destination], resolve: { _ in ConflictResolution(decision: .merge) }
    ).copy(sources: [at(source, "/docs")], to: at(destination, "/"))
    #expect(await destination.text("/docs/new.txt") == "new")
    #expect(await destination.text("/docs/keep.txt") == "keep")
  }

  // MARK: Verification

  @Test func sizeVerificationCatchesATruncatedDestination() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/a.txt", "0123456789")
    await destination.configure(truncateWrites: true)
    _ = try await engine([source, destination]).copy(
      sources: [at(source, "/a.txt")], to: at(destination, "/"))
    await destination.reset()
    await destination.configure(truncateWrites: true)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine([source, destination], verification: .size).copy(
        sources: [self.at(source, "/a.txt")], to: self.at(destination, "/"))
    }
    #expect(await destination.text("/a.txt") == nil)
  }

  @Test func checksumVerificationCatchesSilentCorruption() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/a.txt", "0123456789")
    await destination.configure(corruptWrites: true)
    _ = try await engine([source, destination], verification: .size).copy(
      sources: [at(source, "/a.txt")], to: at(destination, "/"))
    await destination.reset()
    await destination.configure(corruptWrites: true)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine([source, destination], verification: .checksum).copy(
        sources: [self.at(source, "/a.txt")], to: self.at(destination, "/"))
    }
    #expect(await destination.text("/a.txt") == nil)
  }

  @Test func aSourceThatChangesWhileCopyingFails() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/a.txt", "0123456789")
    await source.configure(statSizeLies: 3)
    await #expect(throws: (any Error).self) {
      _ = try await self.engine([source, destination]).copy(
        sources: [self.at(source, "/a.txt")], to: self.at(destination, "/"))
    }
    #expect(await destination.text("/a.txt") == nil)
  }

  // MARK: Control

  @Test func cancellationRemovesTheTemporaryFile() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/big.bin", String(repeating: "x", count: 400))
    await source.configure(readDelay: .milliseconds(20))
    let transfer = engine([source, destination])
    let task = Task {
      try await transfer.copy(sources: [at(source, "/big.bin")], to: at(destination, "/"))
    }
    try await Task.sleep(for: .milliseconds(120))
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await destination.paths().filter { $0 != "/" }.isEmpty)
  }

  @Test func pausingStopsProgressUntilResumed() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/a.txt", "0123456789abcdef")
    let control = TransferControl()
    await control.pause()
    let transfer = engine([source, destination], control: control)
    let task = Task {
      try await transfer.copy(sources: [at(source, "/a.txt")], to: at(destination, "/"))
    }
    try await Task.sleep(for: .milliseconds(150))
    #expect(await destination.text("/a.txt") == nil)
    #expect(await control.bytesTransferred == 0)
    await control.resume()
    _ = try await task.value
    #expect(await destination.text("/a.txt") == "0123456789abcdef")
    #expect(await control.bytesTransferred == 16)
  }

  @Test func aFailureAfterACommittedItemIsReportedAsPartial() async throws {
    let source = MemoryProvider(id: "src")
    let destination = MemoryProvider(id: "dst")
    await source.seedFile("/one.txt", "1")
    await source.seedFile("/two.txt", "twotwotwo")
    await destination.configure(failWritesAfterChunks: 2)
    await #expect(throws: PartialTransferError.self) {
      _ = try await self.engine([source, destination]).copy(
        sources: [self.at(source, "/one.txt"), self.at(source, "/two.txt")],
        to: self.at(destination, "/"))
    }
    #expect(await destination.text("/one.txt") == "1")
  }

  @Test func totalBytesSurvivesServerSizesThatOverflow() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedDirectory("/d")
    await memory.seedFile("/d/a", "x")
    await memory.seedFile("/d/b", "y")
    await memory.seedFile("/c", "z")
    await memory.configure(statSizeLies: .max)
    let total = await engine([memory]).totalBytes(of: [at(memory, "/d"), at(memory, "/c")])
    #expect(total == .max)
  }

  @Test func totalBytesSumsNestedFolders() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedDirectory("/d")
    await memory.seedFile("/d/a", "12345")
    await memory.seedFile("/d/b", "123")
    #expect(await engine([memory]).totalBytes(of: [at(memory, "/d")]) == 8)
  }
}

private actor Counter {
  private(set) var value = 0
  func increment() { value += 1 }
}

/// An in-memory provider with switches for the failures the engine must survive.
actor MemoryProvider: FileSystemProvider {
  nonisolated let id: String
  private struct Node {
    var kind: FileEntry.Kind
    var data = Data()
    var modified = Date(timeIntervalSince1970: 1000)
  }
  private var nodes: [String: Node] = ["/": Node(kind: .directory)]
  private var failAfterChunks: Int?
  private var truncate = false
  private var corrupt = false
  private var lieAboutSize: Int64?
  private var delay: Duration?
  private var failedMoveTarget: String?

  init(id: String) { self.id = id }

  func failMoves(onto path: String) { failedMoveTarget = path }

  func reset() {
    nodes = ["/": Node(kind: .directory)]
    failAfterChunks = nil
    truncate = false
    corrupt = false
    lieAboutSize = nil
    delay = nil
  }

  func configure(
    failWritesAfterChunks: Int? = nil, truncateWrites: Bool = false, corruptWrites: Bool = false,
    statSizeLies: Int64? = nil, readDelay: Duration? = nil
  ) {
    failAfterChunks = failWritesAfterChunks ?? failAfterChunks
    truncate = truncateWrites || truncate
    corrupt = corruptWrites || corrupt
    lieAboutSize = statSizeLies ?? lieAboutSize
    delay = readDelay ?? delay
  }

  func seedFile(_ path: String, _ text: String, modified: Date = Date(timeIntervalSince1970: 1000))
  {
    nodes[path] = Node(kind: .file, data: Data(text.utf8), modified: modified)
  }
  func seedDirectory(_ path: String) { nodes[path] = Node(kind: .directory) }
  func seedLink(_ path: String) { nodes[path] = Node(kind: .symbolicLink) }
  func text(_ path: String) -> String? {
    nodes[path].flatMap { $0.kind == .file ? String(decoding: $0.data, as: UTF8.self) : nil }
  }
  func paths() -> [String] { nodes.keys.sorted() }

  private func entry(_ path: String, _ node: Node) -> FileEntry {
    FileEntry(
      location: Location(providerID: id, path: path),
      name: path == "/" ? "/" : (path as NSString).lastPathComponent, kind: node.kind,
      size: node.kind == .file ? lieAboutSize ?? Int64(node.data.count) : nil,
      modifiedAt: node.modified)
  }

  func list(_ location: Location) throws -> [FileEntry] {
    guard nodes[location.path]?.kind == .directory else { throw FileSystemError.notFound }
    return nodes.filter {
      $0.key != "/"
        && ($0.key as NSString).deletingLastPathComponent
          == (location.path == "/" ? "/" : location.path)
    }.map { entry($0.key, $0.value) }
  }

  func stat(_ location: Location) throws -> FileEntry {
    guard let node = nodes[location.path] else { throw FileSystemError.notFound }
    return entry(location.path, node)
  }

  func read(_ location: Location) throws -> any FileByteReader {
    guard let node = nodes[location.path], node.kind == .file else {
      throw FileSystemError.notFound
    }
    return ChunkReader(data: node.data, delay: delay)
  }

  func write(_ contents: any FileByteReader, to location: Location) async throws {
    let parent = (location.path as NSString).deletingLastPathComponent
    guard nodes[parent.isEmpty ? "/" : parent]?.kind == .directory else {
      throw FileSystemError.notFound
    }
    guard nodes[location.path] == nil else { throw FileSystemError.destinationExists }
    var data = Data()
    var chunks = 0
    nodes[location.path] = Node(kind: .file)
    while let chunk = try await contents.next() {
      chunks += 1
      data.append(chunk)
      nodes[location.path]?.data = data
      if let failAfterChunks, chunks >= failAfterChunks { throw FileSystemError.io("disk full") }
    }
    if truncate { data = data.prefix(max(0, data.count - 1)) }
    if corrupt, !data.isEmpty { data[data.startIndex] = data[data.startIndex] ^ 0xFF }
    nodes[location.path]?.data = data
  }

  func move(_ source: Location, to destination: Location) throws {
    guard let node = nodes[source.path] else { throw FileSystemError.notFound }
    guard nodes[destination.path] == nil else { throw FileSystemError.destinationExists }
    if destination.path == failedMoveTarget { throw FileSystemError.io("move failed") }
    nodes[destination.path] = node
    nodes[source.path] = nil
    for key in nodes.keys where key.hasPrefix(source.path + "/") {
      nodes[destination.path + key.dropFirst(source.path.count)] = nodes.removeValue(forKey: key)
    }
  }

  func delete(_ location: Location) throws {
    guard nodes[location.path] != nil else { throw FileSystemError.notFound }
    for key in nodes.keys where key == location.path || key.hasPrefix(location.path + "/") {
      nodes[key] = nil
    }
  }

  func createDirectory(_ location: Location) throws {
    let parent = (location.path as NSString).deletingLastPathComponent
    guard nodes[parent.isEmpty ? "/" : parent]?.kind == .directory else {
      throw FileSystemError.notFound
    }
    guard nodes[location.path] == nil else { throw FileSystemError.destinationExists }
    nodes[location.path] = Node(kind: .directory)
  }
}

private final class ChunkReader: FileByteReader, @unchecked Sendable {
  private var data: Data
  private let delay: Duration?
  init(data: Data, delay: Duration?) {
    self.data = data
    self.delay = delay
  }
  func next() async throws -> Data? {
    if let delay { try await Task.sleep(for: delay) }
    try Task.checkCancellation()
    guard !data.isEmpty else { return nil }
    let chunk = data.prefix(4)
    data = data.dropFirst(4)
    return Data(chunk)
  }
}
