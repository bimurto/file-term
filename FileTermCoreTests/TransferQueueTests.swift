import Foundation
import Testing

@testable import FileTermCore

@MainActor struct TransferQueueTests {
  @Test func defaultsAndClassification() {
    let preferences = TransferPreferences()
    #expect(preferences.maximumConcurrent == 5)
    #expect(preferences.maximumRetries == 5)
    #expect(preferences.replacePolicy == .ask)
    #expect(!TransferQueue.isTemporary(CocoaError(.fileWriteNoPermission)))
    #expect(!TransferQueue.isTemporary(URLError(.userAuthenticationRequired)))
    #expect(TransferQueue.isTemporary(URLError(.timedOut)))
    #expect(TransferQueue.isTemporary(NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))))
  }

  @Test func aFailedJobIsReportedAndACancelledOneIsNot() async throws {
    let queue = TransferQueue()
    var messages: [String] = []
    queue.onFailure = { messages.append($0.failureMessage) }
    queue.submit(kind: .rename) { _ in throw LocalFileOperationError.destinationExists }
    queue.submit(kind: .copy) { _ in throw CancellationError() }
    queue.submit(kind: .move) { _ in .init(succeeded: 1) }
    while queue.hasPendingWork { try await Task.sleep(for: .milliseconds(5)) }
    #expect(
      messages == [
        "Rename failed: An item already exists at the destination. Nothing was overwritten."
      ])
  }

  @Test func concurrencyReservationsCancellationAndReordering() async throws {
    let queue = TransferQueue()
    queue.preferences.maximumConcurrent = 2
    let first = queue.submit(kind: .copy, resources: ["history"]) { control in
      while true {
        try await control.checkpoint()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    let second = queue.submit(kind: .move, resources: ["history"]) { _ in .init(succeeded: 1) }
    let third = queue.submit(kind: .copy) { control in
      while true {
        try await control.checkpoint()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    let fourth = queue.submit(kind: .copy, resources: ["history"]) { _ in .init(succeeded: 1) }
    #expect(queue.jobs.first { $0.id == first }?.state == .running)
    #expect(queue.jobs.first { $0.id == second }?.state == .queued)
    #expect(queue.jobs.first { $0.id == third }?.state == .running)
    queue.move(fourth, by: -1)
    #expect(queue.jobs.firstIndex { $0.id == fourth }! < queue.jobs.firstIndex { $0.id == second }!)
    queue.pause(second)
    #expect(queue.jobs.first { $0.id == second }?.state == .paused)
    queue.cancel(first)
    queue.cancel(third)
    for _ in 0..<200 {
      if queue.jobs.first(where: { $0.id == fourth })?.state == .completed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(queue.jobs.first { $0.id == fourth }?.state == .completed)
    queue.resume(second)
    for _ in 0..<200 {
      if queue.jobs.first(where: { $0.id == second })?.state == .completed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(queue.jobs.first { $0.id == second }?.summary.succeeded == 1)
    #expect(queue.exportedLogs.contains("Completed"))
  }

  @Test func cancelledJobsRemainPendingUntilCleanupFinishes() async throws {
    let queue = TransferQueue()
    let gate = QueueCleanupGate()
    let id = queue.submit(kind: .copy) { _ in
      gate.entered = true
      while !gate.release { await Task.yield() }
      throw CancellationError()
    }
    while !gate.entered { await Task.yield() }
    queue.cancel(id)
    #expect(queue.hasPendingWork)
    gate.release = true
    for _ in 0..<1000 {
      if !queue.hasPendingWork { break }
      await Task.yield()
    }
    #expect(!queue.hasPendingWork)
    #expect(queue.jobs.first?.state == .cancelled)
  }

  @Test func automaticRetriesOnlyTemporaryErrors() async throws {
    let queue = TransferQueue()
    queue.preferences.automaticallyRetry = true
    queue.preferences.maximumRetries = 1
    var attempts = 0
    queue.submit(kind: .copy) { _ in
      attempts += 1
      if attempts == 1 { throw URLError(.timedOut) }
      return .init(succeeded: 1)
    }
    for _ in 0..<400 {
      if queue.jobs.first?.state == .completed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(attempts == 2)
    #expect(queue.jobs.first?.state == .completed)
    #expect(queue.exportedLogs.contains("retry 1"))
    var permanentAttempts = 0
    queue.submit(kind: .copy) { _ in
      permanentAttempts += 1
      throw CocoaError(.fileNoSuchFile)
    }
    for _ in 0..<100 {
      if queue.jobs.last?.state == .failed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(permanentAttempts == 1)
  }

  @Test func failuresHaveDiagnosticsAndCanBeRetried() async throws {
    let queue = TransferQueue()
    var attempts = 0
    let id = queue.submit(
      kind: .copy, sources: [URL(fileURLWithPath: "/source")],
      destination: URL(fileURLWithPath: "/destination")
    ) { _ in
      attempts += 1
      if attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
      return .init(succeeded: 1)
    }
    for _ in 0..<100 {
      if queue.jobs.first?.state == .failed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(queue.jobs.first?.hint?.contains("permissions") == true)
    queue.retry(id)
    for _ in 0..<100 {
      if queue.jobs.first?.state == .completed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(attempts == 2)
    #expect(queue.exportedLogs.contains("/source"))
    #expect(queue.exportedLogs.contains("/destination"))
  }

  @Test func relayAppliesBothBandwidthBudgets() async throws {
    let queue = TransferQueue()
    queue.preferences.limitUpload = true
    queue.preferences.limitDownload = true
    queue.preferences.uploadBytesPerSecond = 1000
    queue.preferences.downloadBytesPerSecond = 1000
    let clock = ContinuousClock()
    let start = clock.now
    queue.submit(kind: .copy, direction: .relay) { control in
      try await control.advance(bytes: 100)
      return .init(succeeded: 1)
    }
    for _ in 0..<200 {
      if queue.jobs.first?.state == .completed { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(queue.jobs.first?.state == .completed)
    #expect(start.duration(to: clock.now) >= .milliseconds(190))
  }

  @Test func remoteEndpointsAreLabelledInJobsAndLogs() async throws {
    let queue = TransferQueue()
    queue.submit(
      kind: .copy, sourceLabels: ["Office: /a.txt"], destinationLabel: "Backup: /b"
    ) { _ in .init(succeeded: 1) }
    #expect(queue.jobs.first?.sourceLabels == ["Office: /a.txt"])
    #expect(queue.jobs.first?.destinationLabel == "Backup: /b")
    #expect(queue.exportedLogs.contains("Office: /a.txt"))
    #expect(queue.exportedLogs.contains("Backup: /b"))
  }

  @Test func copiesToTheSameServerSerializeButDifferentServersRunTogether() async throws {
    let queue = TransferQueue()
    func blocker() -> TransferQueue.Action {
      { control in
        while true {
          try await control.checkpoint()
          try await Task.sleep(for: .milliseconds(10))
        }
      }
    }
    let first = queue.submit(kind: .copy, resources: ["remote:one"], action: blocker())
    let sameServer = queue.submit(kind: .copy, resources: ["remote:one"], action: blocker())
    let otherServer = queue.submit(kind: .copy, resources: ["remote:two"], action: blocker())
    #expect(queue.jobs.first { $0.id == first }?.state == .running)
    #expect(queue.jobs.first { $0.id == sameServer }?.state == .queued)
    #expect(queue.jobs.first { $0.id == otherServer }?.state == .running)
    for job in queue.jobs { queue.cancel(job.id) }
  }
}

@MainActor private final class QueueCleanupGate {
  var entered = false
  var release = false
}
