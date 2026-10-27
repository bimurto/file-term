import Foundation

/// Single-item edits on any provider: rename, new folder and delete.
public enum ProviderItemOperations {
  public static func rename(_ location: Location, to name: String, registry: ProviderRegistry)
    async throws -> Location
  {
    guard !name.isEmpty, !name.contains("/") else {
      throw FileSystemError.io("Enter a name without slashes.")
    }
    let provider = try provider(location, registry)
    let destination = ProviderTransfer.child(
      Location(providerID: location.providerID, path: ProviderTransfer.parentPath(location.path)),
      name)
    if destination == location { return location }
    do {
      _ = try await provider.stat(destination)
      throw FileSystemError.destinationExists
    } catch FileSystemError.notFound {}
    try await provider.move(location, to: destination)
    return destination
  }

  /// Creates "untitled folder", or "untitled folder 2" and so on when that name is taken.
  public static func createFolder(in folder: Location, registry: ProviderRegistry) async throws
    -> Location
  {
    let provider = try provider(folder, registry)
    for number in 1..<1000 {
      let candidate = ProviderTransfer.child(
        folder, number == 1 ? "untitled folder" : "untitled folder \(number)")
      do {
        _ = try await provider.stat(candidate)
      } catch FileSystemError.notFound {
        try await provider.createDirectory(candidate)
        return candidate
      }
    }
    throw FileSystemError.destinationExists
  }

  private static func provider(_ location: Location, _ registry: ProviderRegistry) throws
    -> any FileSystemProvider
  {
    guard let provider = registry.provider(for: location.providerID) else {
      throw FileSystemError.unsupportedOperation
    }
    return provider
  }
}
