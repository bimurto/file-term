import Foundation

public enum CopyVerification: String, Codable, CaseIterable, Sendable {
  case none, size, checksum
}

/// Cooperative, in-process control. Pausing retains the task's open file handles;
/// partial files are never reused across process launches.
public actor TransferControl {
  public private(set) var bytesTransferred: Int64 = 0
  private var paused = false
  private var cancelled = false
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private let bytesPerSecond: Int64?
  private let progress: @Sendable (Int64) async -> Void
  private let throttle: @Sendable (Int64) async throws -> Void

  public init(
    bytesPerSecond: Int64? = nil,
    progress: @escaping @Sendable (Int64) async -> Void = { _ in },
    throttle: @escaping @Sendable (Int64) async throws -> Void = { _ in }
  ) {
    self.bytesPerSecond = bytesPerSecond.flatMap { $0 > 0 ? $0 : nil }
    self.progress = progress
    self.throttle = throttle
  }

  public func pause() { paused = true }

  public func resume() {
    paused = false
    let pending = waiters.values
    waiters.removeAll()
    for waiter in pending { waiter.resume() }
  }

  public func cancel() {
    cancelled = true
    let pending = waiters.values
    waiters.removeAll()
    for waiter in pending { waiter.resume(throwing: CancellationError()) }
  }

  public func checkpoint() async throws {
    try Task.checkCancellation()
    if cancelled { throw CancellationError() }
    while paused {
      let id = UUID()
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          waiters[id] = continuation
        }
      } onCancel: {
        Task { await self.cancelWaiter(id) }
      }
      try Task.checkCancellation()
      if cancelled { throw CancellationError() }
    }
  }

  private func cancelWaiter(_ id: UUID) {
    waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  public func advance(bytes: Int64) async throws {
    try await checkpoint()
    guard bytes > 0 else { return }
    try await throttle(bytes)
    try await checkpoint()
    bytesTransferred += bytes
    await progress(bytesTransferred)
    if let rate = bytesPerSecond {
      // Short slices keep explicit cancellation responsive even at very low rates.
      var remaining = Double(bytes) / Double(rate)
      while remaining > 0 {
        try await checkpoint()
        let slice = min(remaining, 0.05)
        try await Task.sleep(for: .seconds(slice))
        remaining -= slice
      }
    }
    try await checkpoint()
  }
}
