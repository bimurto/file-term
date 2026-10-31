import Darwin
import Foundation
import Testing

@testable import FileTermCore

/// M14.12 targets: a 100k folder is usable within 3 s, and nothing holds the main thread for more
/// than 250 ms during a large transfer. Writes large temporary fixtures, so skipped unless
/// FILETERM_PERF=1. Debug numbers are pessimistic: run with `swift test -c release -Xswiftc
/// -enable-testing --filter PerformanceBenchmarks`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FILETERM_PERF"] == "1"), .serialized)
@MainActor struct PerformanceBenchmarks {
  /// Measures the longest time the main actor couldn't run anything else.
  @MainActor private final class StallMonitor {
    private(set) var worst = Duration.zero
    private var task: Task<Void, Never>?

    func start() {
      task = Task { @MainActor [weak self] in
        let tick = Duration.milliseconds(5)
        while !Task.isCancelled {
          let before = ContinuousClock.now
          try? await Task.sleep(for: tick)
          let late = ContinuousClock.now - before - tick
          if let self, late > self.worst { self.worst = late }
        }
      }
    }

    func stop() { task?.cancel() }
  }

  private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-perf-\(UUID().uuidString)"
    ).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func report(_ name: String, _ value: Duration) {
    let seconds = Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
    print("PERF \(name): \(String(format: "%.3f", seconds)) s")
  }

  private func timed<T: Sendable>(_ name: String, _ body: () async throws -> T) async rethrows -> T
  {
    let start = ContinuousClock.now
    let result = try await body()
    report(name, ContinuousClock.now - start)
    return result
  }

  @Test func aFolderWith100kEntriesListsWithinTheTarget() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await timed("create 100k files") {
      for index in 0..<100_000 {
        let descriptor = open(
          folder.appendingPathComponent("file \(index).txt").path, O_WRONLY | O_CREAT, 0o644)
        close(descriptor)
      }
    }
    let provider = LocalFileSystemProvider()
    let location = provider.location(for: folder)
    let listed = try await timed("provider list") { try await provider.list(location) }
    #expect(listed.count == 100_000)

    let pane = PaneModel(providers: [provider])
    let monitor = StallMonitor()
    monitor.start()
    let start = ContinuousClock.now
    #expect(await pane.navigate(to: location))
    // What each view reads while drawing, so usable means all of it has been computed once.
    let list = pane.displayEntries
    let groups = pane.entryGroups
    let total = ContinuousClock.now - start
    // The monitor can only notice a stall once the main actor is free again.
    try await Task.sleep(for: .milliseconds(50))
    monitor.stop()
    #expect(list.count == 100_000 && groups.flatMap(\.entries).count == 100_000)

    report("navigate and first draw data", total)
    report("worst main thread stall", monitor.worst)
    await timed("visibleEntries") { _ = pane.visibleEntries }
    await timed("displayEntries") { _ = pane.displayEntries }
    await timed("entryGroups") { _ = pane.entryGroups }
    await timed("selectedEntries, nothing selected") { _ = pane.selectedEntries }
    pane.selection = [list[0].id]
    await timed("selectedEntries, one selected") { _ = pane.selectedEntries }
    #expect(total < .seconds(3))
  }

  @Test func aLargeTransferLeavesTheMainThreadFree() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("large.bin")
    let target = folder.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    #expect(FileManager.default.createFile(atPath: source.path, contents: nil))
    let handle = try FileHandle(forWritingTo: source)
    try handle.truncate(atOffset: 1 << 30)
    try handle.close()

    let provider = LocalFileSystemProvider()
    let registry = ProviderRegistry(providers: [provider])
    let queue = TransferQueue()
    let monitor = StallMonitor()
    monitor.start()
    let start = ContinuousClock.now
    let id = queue.submit(kind: .copy) { control in
      try await ProviderTransfer(registry: registry, control: control).copy(
        sources: [provider.location(for: source)], to: provider.location(for: target))
    }
    while queue.jobs.first(where: { $0.id == id })?.state.isTerminal == false {
      try await Task.sleep(for: .milliseconds(20))
    }
    report("copy 1 GB", ContinuousClock.now - start)
    monitor.stop()
    report("worst main thread stall during transfer", monitor.worst)
    #expect(queue.jobs.first { $0.id == id }?.state == .completed)
    let copied = target.appendingPathComponent("large.bin")
    #expect(try copied.resourceValues(forKeys: [.fileSizeKey]).fileSize == 1 << 30)
    #expect(monitor.worst < .milliseconds(250))
  }
}
