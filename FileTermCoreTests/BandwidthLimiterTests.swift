import Foundation
import Testing

@testable import FileTermCore

struct BandwidthLimiterTests {
  @Test func sharedBudgetThrottlesConcurrentConsumers() async throws {
    let limiter = BandwidthLimiter()
    await limiter.configure(bytesPerSecond: 1000)
    let clock = ContinuousClock()
    let start = clock.now
    async let first: Void = limiter.consume(100)
    async let second: Void = limiter.consume(100)
    _ = try await (first, second)
    #expect(start.duration(to: clock.now) >= .milliseconds(190))
  }

  @Test func disabledBudgetDoesNotDelay() async throws {
    let limiter = BandwidthLimiter()
    await limiter.configure(bytesPerSecond: nil)
    try await limiter.consume(Int64.max)
  }
}
