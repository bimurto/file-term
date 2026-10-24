import Foundation
import Observation

@MainActor
@Observable public final class PaneModel {
  public let id = UUID()
  public var isPinned = false
  public var viewScope: ViewSettingsScope = .tab
  public var tabViewOptions: ViewOptions
  public let viewPreferences: ViewPreferences
  public var viewOptions: ViewOptions {
    get {
      viewScope == .folder
        ? location.flatMap { viewPreferences.folders[$0] } ?? viewPreferences.defaults
        : tabViewOptions
    }
    set {
      if viewScope == .folder, let location {
        viewPreferences.folders[location] = newValue
      } else {
        tabViewOptions = newValue
      }
    }
  }
  public var displayEntries: [FileEntry] { entries.sorted(using: viewOptions.order) }
  public var entryGroups: [EntryGroup] {
    EntryGrouping.groups(entries, by: viewOptions.groupField, order: viewOptions.order)
  }
  public func saveViewSettingsAsDefaults() { viewPreferences.defaults = viewOptions }
  public func restoreDefaultViewSettings() { viewOptions = viewPreferences.defaults }

  public private(set) var location: Location?
  public private(set) var entries: [FileEntry] = []
  public var selection: Set<Location> = []
  public private(set) var isLoading = false
  public private(set) var errorMessage: String?
  public private(set) var navigationRevision = UUID()
  private var history: [Location] = []
  private var historyIndex = -1
  @ObservationIgnored private let providers: [String: any FileSystemProvider]

  public init(
    providers: [any FileSystemProvider], viewPreferences: ViewPreferences = ViewPreferences()
  ) {
    self.viewPreferences = viewPreferences
    tabViewOptions = viewPreferences.defaults
    self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
  }

  public var canGoBack: Bool { historyIndex > 0 }
  public var canGoForward: Bool { historyIndex + 1 < history.count }
  public var canGoUp: Bool { location?.parent != nil }
  public var selectedEntries: [FileEntry] { entries.filter { selection.contains($0.id) } }
  public var selectedBytes: Int64 { selectedEntries.compactMap(\.size).reduce(0, +) }
  public var hasUnknownSelectedSizes: Bool { selectedEntries.contains { $0.size == nil } }

  @discardableResult public func navigate(to destination: Location) async -> Bool {
    await load(destination, historyIndex: nil)
  }

  @discardableResult public func goBack() async -> Bool {
    guard canGoBack else { return false }
    return await load(history[historyIndex - 1], historyIndex: historyIndex - 1)
  }

  @discardableResult public func goForward() async -> Bool {
    guard canGoForward else { return false }
    return await load(history[historyIndex + 1], historyIndex: historyIndex + 1)
  }

  @discardableResult public func goUp() async -> Bool {
    guard let parent = location?.parent else { return false }
    return await navigate(to: parent)
  }

  public func cancelPendingNavigation() {
    navigationRevision = UUID()
    isLoading = false
  }

  private func load(_ destination: Location, historyIndex newIndex: Int?) async -> Bool {
    let request = UUID()
    navigationRevision = request
    isLoading = true
    errorMessage = nil
    do {
      guard let provider = providers[destination.providerID] else {
        throw FileSystemError.unsupportedOperation
      }
      let listing = try await provider.list(destination)
      try Task.checkCancellation()
      guard navigationRevision == request else { return false }
      entries = listing.sorted {
        if ($0.kind == .directory) != ($1.kind == .directory) {
          return $0.kind == .directory
        }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      if let newIndex {
        historyIndex = newIndex
      } else if location != destination {
        history = Array(history.prefix(historyIndex + 1))
        history.append(destination)
        historyIndex = history.count - 1
      }
      location = destination
      selection = []
      isLoading = false
      return true
    } catch {
      guard navigationRevision == request else { return false }
      isLoading = false
      if !(error is CancellationError) { errorMessage = error.localizedDescription }
      return false
    }
  }
}

extension Location {
  public var parent: Location? {
    guard path.hasPrefix("/"), path != "/" else { return nil }
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    return Location(providerID: providerID, path: parent.isEmpty ? "/" : parent)
  }
}
