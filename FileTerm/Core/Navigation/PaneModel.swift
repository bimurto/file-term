import Foundation
import Observation

@MainActor
@Observable public final class PaneModel {
  public private(set) var location: Location?
  public private(set) var entries: [FileEntry] = []
  public var selection: Set<Location> = []
  public private(set) var isLoading = false
  public private(set) var errorMessage: String?
  @ObservationIgnored private let providers: [String: any FileSystemProvider]
  @ObservationIgnored private var requestID = UUID()

  public init(providers: [any FileSystemProvider]) {
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
  }

  public func navigate(to destination: Location) async {
    let request = UUID()
    requestID = request
    isLoading = true
    errorMessage = nil
    do {
      guard let provider = providers[destination.providerID] else {
        throw FileSystemError.unsupportedOperation
      }
      let listing = try await provider.list(destination)
      try Task.checkCancellation()
      guard requestID == request else { return }
      entries = listing.sorted {
        if ($0.kind == .directory) != ($1.kind == .directory) {
          return $0.kind == .directory
        }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      location = destination
      selection = []
      isLoading = false
    } catch {
      guard requestID == request else { return }
      isLoading = false
      if !(error is CancellationError) { errorMessage = error.localizedDescription }
    }
  }
}
