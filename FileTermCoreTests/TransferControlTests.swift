import Foundation
import Testing

@testable import FileTermCore

struct TransferControlTests {
  @Test func cancellationWakesPausedCheckpoint() async throws {
    let control = TransferControl()
    await control.pause()
    let waiting = Task { try await control.checkpoint() }
    await control.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
    await control.resume()
    await #expect(throws: CancellationError.self) { try await control.advance(bytes: 1) }
    #expect(await control.bytesTransferred == 0)
  }

  @Test func taskCancellationWakesPausedCheckpoint() async throws {
    let control = TransferControl()
    await control.pause()
    let waiting = Task { try await control.checkpoint() }
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
  }

  @Test func mergeCountsChildOutcomesAndKeepsCompletedWorkUndoableAfterStop() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    let merged = target.appendingPathComponent("source")
    try fm.createDirectory(at: source, withIntermediateDirectories: false)
    try fm.createDirectory(at: merged, withIntermediateDirectories: true)
    for name in ["a", "b", "c"] {
      try Data(name.utf8).write(to: source.appendingPathComponent(name))
    }
    for name in ["b", "c"] {
      try Data("old".utf8).write(to: merged.appendingPathComponent(name))
    }
    let operations = LocalFileOperations()
    await operations.setTransferControl(TransferControl())
    await #expect(throws: CancellationError.self) {
      try await operations.transfer(sources: [source], to: target, move: false) { conflict in
        ConflictResolution(
          decision: conflict.isDirectoryMerge
            ? .merge : conflict.source.lastPathComponent == "b" ? .skip : .stop)
      }
    }
    let summary = await operations.outcomeSummary()
    #expect(summary.succeeded == 1)
    #expect(summary.skipped == 1)
    #expect(summary.failed == 0)
    #expect(fm.fileExists(atPath: merged.appendingPathComponent("a").path))
    try await operations.undo()
    #expect(!fm.fileExists(atPath: merged.appendingPathComponent("a").path))
  }

  @Test func stopIsCancellationAndSkipIsCounted() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data("source".utf8).write(to: source)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    try Data("old".utf8).write(to: target.appendingPathComponent("source"))
    let operations = LocalFileOperations()
    _ = try await operations.transfer(sources: [source], to: target, move: false)
    #expect(await operations.outcomeSummary().skipped == 1)
    await operations.setTransferControl(TransferControl())
    await #expect(throws: CancellationError.self) {
      try await operations.transfer(sources: [source], to: target, move: false) { _ in
        ConflictResolution(decision: .stop)
      }
    }
    #expect(await operations.outcomeSummary().failed == 0)
  }

  @Test func throttleRunsBeforeProgress() async throws {
    let values = ProgressValues()
    let control = TransferControl(
      progress: { await values.append($0 + 100) },
      throttle: { await values.append($0) })
    try await control.advance(bytes: 5)
    #expect(await values.values == [5, 105])
  }

  @Test func resumeReleasesPausedWorkAndReportsCumulativeProgress() async throws {
    let values = ProgressValues()
    let control = TransferControl(progress: { await values.append($0) })
    await control.pause()
    let task = Task { try await control.advance(bytes: 13) }
    #expect(await control.bytesTransferred == 0)
    await control.resume()
    try await task.value
    try await control.advance(bytes: 7)
    #expect(await control.bytesTransferred == 20)
    #expect(await values.values == [13, 20])
  }

  @Test func crossDeviceCancellationPreservesSourceAndPublishesNothing() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data(repeating: 5, count: 300_000).write(to: source)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    let operations = LocalFileOperations(
      rename: { from, to in
        if from == source { throw NSError(domain: NSPOSIXErrorDomain, code: 18) }
        try LocalFileOperations.exclusiveRename(from, to)
      }, remove: { try FileManager.default.removeItem(at: $0) })
    let relay = CancellationRelay()
    let control = TransferControl(progress: { _ in await relay.cancel() })
    await relay.set(control)
    await operations.setTransferControl(control)
    await #expect(throws: CancellationError.self) {
      try await operations.transfer(sources: [source], to: target, move: true)
    }
    #expect(try Data(contentsOf: source).count == 300_000)
    #expect(try fm.contentsOfDirectory(atPath: target.path).isEmpty)
    #expect(await operations.outcomeSummary().succeeded == 0)
  }

  @Test func sourceModificationDuringCopyIsNotPublished() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data(repeating: 7, count: 300_000).write(to: source)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    let control = TransferControl(progress: { _ in
      try? Data("changed".utf8).write(to: source)
    })
    let operations = LocalFileOperations()
    await operations.setTransferControl(control, verification: .checksum)
    await #expect(throws: (any Error).self) {
      try await operations.transfer(sources: [source], to: target, move: false)
    }
    #expect(try fm.contentsOfDirectory(atPath: target.path).isEmpty)
    #expect(try String(contentsOf: source, encoding: .utf8) == "changed")
  }

  @Test func copiedBytesAndMetadataAndSymlinksArePreserved() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try fm.createDirectory(at: source, withIntermediateDirectories: false)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    let file = source.appendingPathComponent("data")
    let payload = Data(repeating: 42, count: 200_003)
    try payload.write(to: file)
    try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
    try fm.createSymbolicLink(
      atPath: source.appendingPathComponent("link").path, withDestinationPath: "missing")
    let control = TransferControl()
    let operations = LocalFileOperations()
    await operations.setTransferControl(control, verification: .checksum)
    let copied = try #require(
      try await operations.transfer(sources: [source], to: target, move: false).first)
    #expect(await control.bytesTransferred == Int64(payload.count))
    #expect(try Data(contentsOf: copied.appendingPathComponent("data")) == payload)
    #expect(
      try fm.destinationOfSymbolicLink(atPath: copied.appendingPathComponent("link").path)
        == "missing")
    #expect(
      (try fm.attributesOfItem(atPath: copied.appendingPathComponent("data").path)[
        .posixPermissions] as? NSNumber)?.intValue == 0o640)
    try await operations.undo()
    #expect(!fm.fileExists(atPath: copied.path))
    try await operations.redo()
    #expect(fm.fileExists(atPath: copied.path))
  }

  @Test func cancellationDuringCopyDoesNotPublishPartialDestination() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    try Data(repeating: 7, count: 300_000).write(to: source)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    let relay = CancellationRelay()
    let operations = LocalFileOperations()
    let cancelling = TransferControl(progress: { _ in await relay.cancel() })
    await relay.set(cancelling)
    await operations.setTransferControl(cancelling)
    await #expect(throws: CancellationError.self) {
      try await operations.transfer(sources: [source], to: target, move: false)
    }
    #expect(await cancelling.bytesTransferred == 65_536)
    #expect(try fm.contentsOfDirectory(atPath: target.path).isEmpty)
    #expect(try Data(contentsOf: source).count == 300_000)
  }
}

private actor ProgressValues {
  var values: [Int64] = []
  func append(_ value: Int64) { values.append(value) }
}

private actor CancellationRelay {
  var control: TransferControl?
  func set(_ control: TransferControl) { self.control = control }
  func cancel() async { await control?.cancel() }
}
