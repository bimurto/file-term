import Foundation

/// The providers panes can navigate through. Shared by every pane and tab so connections opened
/// at runtime are visible everywhere.
public final class ProviderRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var providers: [String: any FileSystemProvider] = [:]
  private var containers: [String: Location] = [:]

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
    containers[id] = nil
  }

  /// Where Go Up leads from the root of a provider that lives inside another location, such as
  /// an archive opened as a folder.
  public func setContainer(_ container: Location, for providerID: String) {
    lock.lock()
    defer { lock.unlock() }
    containers[providerID] = container
  }

  public func container(of providerID: String) -> Location? {
    lock.lock()
    defer { lock.unlock() }
    return containers[providerID]
  }

  public func providerIDs(withPrefix prefix: String) -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return providers.keys.filter { $0.hasPrefix(prefix) }
  }

  public func provider(for id: String) -> (any FileSystemProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return providers[id]
  }
}
