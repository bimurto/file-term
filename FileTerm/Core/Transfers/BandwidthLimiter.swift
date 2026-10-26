import Foundation

public enum TransferDirection: Sendable {
  case local, upload, download
}

/// Reserves time on one shared directional budget; concurrent jobs cannot multiply the limit.
public actor BandwidthLimiter {
  private let clock = ContinuousClock()
  private var available: ContinuousClock.Instant?
  private var rate: Int64 = 0
  public init() {}

  public func configure(bytesPerSecond: Int64?) {
    let newRate = max(0, bytesPerSecond ?? 0)
    if newRate != rate {
      rate = newRate
      available = nil
    }
  }

  public func consume(_ bytes: Int64) async throws {
    try Task.checkCancellation()
    guard rate > 0, bytes > 0 else { return }
    let now = clock.now
    let start = max(now, available ?? now)
    let end = start.advanced(by: .seconds(Double(bytes) / Double(rate)))
    available = end
    try await clock.sleep(until: end)
  }
}
