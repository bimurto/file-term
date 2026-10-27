import Foundation

/// The providers panes can navigate through. Shared by every pane and tab so connections opened
/// at runtime are visible everywhere.
public final class ProviderRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var providers: [String: any FileSystemProvider] = [:]

  public init(providers: [any FileSystemProvider] = []) {
    for provider in providers { self.providers[provider.id] = provider }
  }

  public func register(_ provider: any FileSystemProvider) {
    lock.lock()
    defer { lock.unlock() }
    providers[provider.id] = provider
  }

  public func unregister(id: String) {
    lock.lock()
    defer { lock.unlock() }
    providers[id] = nil
  }

  public func provider(for id: String) -> (any FileSystemProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return providers[id]
  }
}
