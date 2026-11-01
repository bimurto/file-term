import Foundation
import Observation

public enum TransferJobState: String, Sendable {
  case queued, running, paused, completed, failed, cancelled
  public var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

public enum TransferJobKind: String, Sendable {
  case copy, move, rename, delete, compress, extract, create, duplicate, open, undo, redo
  case tool, upload, git
}

public struct PartialTransferError: Error, LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? {
    message + " Completed changes are undoable; inspect them before submitting the remaining items."
  }
}

public struct TransferSummary: Sendable {
  public var succeeded = 0
  public var skipped = 0
  public var failed = 0
  public init(succeeded: Int = 0, skipped: Int = 0, failed: Int = 0) {
    self.succeeded = succeeded
    self.skipped = skipped
    self.failed = failed
  }
}

public struct TransferJob: Identifiable, Sendable {
  public let id: UUID
  public let kind: TransferJobKind
  public let sources: [URL]
  public let destination: URL?
  /// Human-readable endpoints, which also describe locations that have no file URL.
  public let sourceLabels: [String]
  public let destinationLabel: String?
  public var state: TransferJobState = .queued
  public var bytesTransferred: Int64 = 0
  public var bytesPerSecond: Double = 0
  public var totalBytes: Int64?
  public var summary = TransferSummary()
  public var error: String?
  public var hint: String?
  public var attempts = 0
  public var canRetry = true
  public var startedAt: Date?
  /// What to tell the user when this job fails, for those who don't have Activities open.
  public var failureMessage: String {
    "\(kind.rawValue.capitalized) failed: \(error ?? "Unknown error.")"
  }
  public var eta: Double? {
    guard let totalBytes, bytesPerSecond > 0 else { return nil }
    return Double(max(0, totalBytes - bytesTransferred)) / bytesPerSecond
  }
}

public struct TransferLogEntry: Identifiable, Sendable {
  public let id = UUID()
  public let timestamp = Date()
  public let jobID: UUID
  public let source: String
  public let destination: String
  public let message: String
  public var text: String {
    "\(timestamp.ISO8601Format())\t\(source)\t\(destination)\t\(message)"
  }
}

/// App-wide scheduler. Resources are explicit reservations; history mutations reserve a common key.
@MainActor @Observable public final class TransferQueue {
  public typealias Action = @MainActor (TransferControl) async throws -> TransferSummary
  public private(set) var jobs: [TransferJob] = []
  public private(set) var logs: [TransferLogEntry] = []
  public var preferences = TransferPreferences() { didSet { schedule() } }
  /// Called when a job fails, not when it's cancelled.
  @ObservationIgnored public var onFailure: ((TransferJob) -> Void)?
  @ObservationIgnored private var actions: [UUID: Action] = [:]
  @ObservationIgnored private var controls: [UUID: TransferControl] = [:]
  @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var reservations: [UUID: Set<String>] = [:]
  @ObservationIgnored private var active: Set<UUID> = []
  @ObservationIgnored private var directions: [UUID: TransferDirection] = [:]
  @ObservationIgnored private let uploadLimiter = BandwidthLimiter()
  @ObservationIgnored private let downloadLimiter = BandwidthLimiter()
  public init() {}
  public var hasPendingWork: Bool { !active.isEmpty || jobs.contains { !$0.state.isTerminal } }

  @discardableResult public func submit(
    kind: TransferJobKind, sources: [URL] = [], destination: URL? = nil,
    resources: Set<String> = [], totalBytes: Int64? = nil, retrySafe: Bool = true,
    direction: TransferDirection = .local, sourceLabels: [String]? = nil,
    destinationLabel: String? = nil,
    action: @escaping Action
  ) -> UUID {
    let id = UUID()
    var job = TransferJob(
      id: id, kind: kind, sources: sources, destination: destination,
      sourceLabels: sourceLabels ?? sources.map(\.path),
      destinationLabel: destinationLabel ?? destination?.path)
    job.totalBytes = totalBytes
    job.canRetry = retrySafe
    jobs.append(job)
    actions[id] = action
    directions[id] = direction
    reservations[id] = resources
    log(id, "Queued \(kind.rawValue)")
    schedule()
    return id
  }

  public func log(_ id: UUID, _ message: String) {
    guard let job = jobs.first(where: { $0.id == id }) else { return }
    logs.append(
      TransferLogEntry(
        jobID: id, source: LogRedactor.redact(job.sourceLabels.joined(separator: ", ")),
        destination: LogRedactor.redact(job.destinationLabel ?? ""),
        message: LogRedactor.redact(message)))
  }
  public var exportedLogs: String { logs.map(\.text).joined(separator: "\n") }
  public func exportedLogs(hidingPersonalPaths: Bool) -> String {
    hidingPersonalPaths ? LogRedactor.hidingPersonalPaths(exportedLogs) : exportedLogs
  }

  public func setTotalBytes(_ id: UUID, _ bytes: Int64?) {
    guard let i = index(id) else { return }
    jobs[i].totalBytes = bytes
  }

  public func setSummary(_ id: UUID, _ summary: TransferSummary) {
    guard let i = index(id) else { return }
    jobs[i].summary = summary
  }

  public func pause(_ id: UUID) {
    guard let i = index(id), jobs[i].state == .running || jobs[i].state == .queued else { return }
    jobs[i].state = .paused
    let control = controls[id]
    Task { await control?.pause() }
    log(id, "Paused")
  }

  public func resume(_ id: UUID) {
    guard let i = index(id), jobs[i].state == .paused else { return }
    jobs[i].state = active.contains(id) ? .running : .queued
    let control = controls[id]
    Task { await control?.resume() }
    log(id, "Resumed")
    schedule()
  }

  public func cancel(_ id: UUID) {
    guard let i = index(id), !jobs[i].state.isTerminal else { return }
    jobs[i].state = .cancelled
    tasks[id]?.cancel()
    let control = controls[id]
    Task { await control?.cancel() }
    log(id, "Cancelled")
    schedule()
  }

  public func retry(_ id: UUID) {
    guard let i = index(id), jobs[i].state == .failed, jobs[i].canRetry, !active.contains(id) else {
      return
    }
    jobs[i].state = .queued
    jobs[i].bytesTransferred = 0
    jobs[i].bytesPerSecond = 0
    jobs[i].summary = TransferSummary()
    jobs[i].error = nil
    jobs[i].hint = nil
    log(id, "Manual retry")
    schedule()
  }

  public func move(_ id: UUID, by offset: Int) {
    guard let i = index(id), jobs[i].state == .queued else { return }
    let queued = jobs.indices.filter { jobs[$0].state == .queued }
    guard let position = queued.firstIndex(of: i), queued.indices.contains(position + offset) else {
      return
    }
    jobs.swapAt(i, queued[position + offset])
  }

  private func index(_ id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }
  private func schedule() {
    for job in jobs where job.state == .queued && !active.contains(job.id) {
      guard active.count < max(1, min(64, preferences.maximumConcurrent)) else { break }
      let resources = reservations[job.id] ?? []
      guard
        !active.contains(where: { activeID in
          (reservations[activeID] ?? []).contains { reserved in
            resources.contains { path in
              path == "*" || reserved == "*" || path == "/" || reserved == "/" || path == reserved
                || path.hasPrefix(reserved + "/") || reserved.hasPrefix(path + "/")
            }
          }
        })
      else { continue }
      start(job.id)
    }
  }

  private func start(_ id: UUID) {
    guard let i = index(id), let action = actions[id] else { return }
    active.insert(id)
    jobs[i].state = .running
    jobs[i].startedAt = Date()
    jobs[i].attempts += 1
    let direction = directions[id] ?? .local
    let uploadRate = preferences.limitUpload ? max(1, preferences.uploadBytesPerSecond) : nil
    let downloadRate = preferences.limitDownload ? max(1, preferences.downloadBytesPerSecond) : nil
    let upload = uploadLimiter
    let download = downloadLimiter
    let control = TransferControl(
      progress: { [weak self] bytes in
        await self?.progress(id, bytes: bytes)
      },
      throttle: { bytes in
        switch direction {
        case .local: break
        case .upload:
          await upload.configure(bytesPerSecond: uploadRate)
          try await upload.consume(bytes)
        case .download:
          await download.configure(bytesPerSecond: downloadRate)
          try await download.consume(bytes)
        case .relay:
          await download.configure(bytesPerSecond: downloadRate)
          try await download.consume(bytes)
          await upload.configure(bytesPerSecond: uploadRate)
          try await upload.consume(bytes)
        }
      })
    controls[id] = control
    log(id, "Running")
    tasks[id] = Task { [weak self] in
      guard let self else { return }
      do {
        var retries = 0
        let summary: TransferSummary
        while true {
          do {
            summary = try await action(control)
            break
          } catch {
            guard !(error is CancellationError), Self.isTemporary(error),
              preferences.automaticallyRetry, jobs.first(where: { $0.id == id })?.canRetry == true,
              retries < max(0, min(100, preferences.maximumRetries))
            else { throw error }
            retries += 1
            if let i = index(id) { jobs[i].attempts += 1 }
            log(id, "Temporary error; retry \(retries): \(error.localizedDescription)")
            try await Task.sleep(for: .seconds(min(30, pow(2, Double(retries - 1)))))
            try await control.checkpoint()
          }
        }
        if let i = index(id), jobs[i].state != .cancelled {
          jobs[i].summary = summary
          jobs[i].state = .completed
          log(
            id,
            "Completed: \(summary.succeeded) succeeded, \(summary.skipped) skipped, \(summary.failed) failed"
          )
        }
      } catch {
        if let i = index(id), jobs[i].state != .cancelled {
          if error is CancellationError {
            jobs[i].state = .cancelled
            log(id, "Cancelled")
          } else {
            jobs[i].state = .failed
            if error is PartialTransferError { jobs[i].canRetry = false }
            jobs[i].summary.failed = max(1, jobs[i].summary.failed)
            jobs[i].error = error.localizedDescription
            jobs[i].hint = Self.hint(for: error)
            log(id, "Failed: \(error.localizedDescription)")
            onFailure?(jobs[i])
          }
        }
      }
      active.remove(id)
      tasks[id] = nil
      controls[id] = nil
      schedule()
    }
  }

  private func progress(_ id: UUID, bytes: Int64) {
    guard let i = index(id), !jobs[i].state.isTerminal else { return }
    jobs[i].bytesTransferred = bytes
    let elapsed = max(0.001, Date().timeIntervalSince(jobs[i].startedAt ?? Date()))
    jobs[i].bytesPerSecond = Double(bytes) / elapsed
  }

  public static func isTemporary(_ error: Error) -> Bool {
    let error = error as NSError
    if error.domain == NSURLErrorDomain {
      return [
        NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
        NSURLErrorNotConnectedToInternet,
      ].contains(error.code)
    }
    if error.domain == NSPOSIXErrorDomain {
      return [Int(ETIMEDOUT), Int(ECONNRESET), Int(ECONNABORTED), Int(ENETDOWN), Int(ENETUNREACH)]
        .contains(error.code)
    }
    return false
  }

  public static func hint(for error: Error) -> String {
    let error = error as NSError
    if isTemporary(error) { return "Check connectivity and retry." }
    if error.domain == NSURLErrorDomain && error.code == NSURLErrorUserAuthenticationRequired {
      return "Check credentials."
    }
    if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC)
      || error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError
    {
      return "Check free space on the destination volume."
    }
    return "Check source and destination paths and permissions."
  }
}
