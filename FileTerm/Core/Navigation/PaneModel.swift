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
  /// What the content views show: search results while a search scope is open, else the folder.
  public var calculatedSizes: [Location: Int64] = [:]
  public func setCalculatedSize(_ bytes: Int64, for location: Location) {
    calculatedSizes[location] = bytes
  }
  public var visibleEntries: [FileEntry] {
    (searchScope?.results ?? entries).map { entry in
      var entry = entry
      if entry.kind == .directory, let size = calculatedSizes[entry.id] { entry.size = size }
      return entry
    }
  }
  public var displayEntries: [FileEntry] { visibleEntries.sorted(using: viewOptions.order) }
  public var entryGroups: [EntryGroup] {
    EntryGrouping.groups(visibleEntries, by: viewOptions.groupField, order: viewOptions.order)
  }
  public func saveViewSettingsAsDefaults() { viewPreferences.defaults = viewOptions }
  public func restoreDefaultViewSettings() { viewOptions = viewPreferences.defaults }

  public private(set) var location: Location?
  public private(set) var entries: [FileEntry] = []
  public var selection: Set<Location> = []
  public var renamingLocation: Location?
  @ObservationIgnored public var onRename: ((Location, String) -> Void)?
  public private(set) var searchScope: SearchScope?
  @ObservationIgnored private var folderSelection: Set<Location> = []
  @ObservationIgnored private var searchTask: Task<Void, Never>?
  /// Runs Spotlight searches; installed by the app because it needs AppKit-era frameworks.
  @ObservationIgnored public var spotlightRunner:
    (@Sendable (SearchQuery, Location) async throws -> [FileEntry])?
  public private(set) var isLoading = false
  public private(set) var errorMessage: String?
  /// The folder macOS or a server refused to open, while `errorMessage` describes that refusal.
  public private(set) var deniedLocation: Location?
  public private(set) var navigationRevision = UUID()
  private var history: [Location] = []
  private var historyIndex = -1
  @ObservationIgnored private let registry: ProviderRegistry

  public init(registry: ProviderRegistry, viewPreferences: ViewPreferences = ViewPreferences()) {
    self.viewPreferences = viewPreferences
    tabViewOptions = viewPreferences.defaults
    self.registry = registry
  }

  public convenience init(
    providers: [any FileSystemProvider], viewPreferences: ViewPreferences = ViewPreferences()
  ) {
    self.init(registry: ProviderRegistry(providers: providers), viewPreferences: viewPreferences)
  }

  public func duplicate() -> PaneModel {
    let pane = PaneModel(registry: registry, viewPreferences: viewPreferences)
    pane.location = location
    pane.entries = entries
    pane.tabViewOptions = viewOptions
    pane.viewScope = viewScope
    if let location {
      pane.history = [location]
      pane.historyIndex = 0
    }
    return pane
  }

  public var backLocation: Location? { canGoBack ? history[historyIndex - 1] : nil }
  public var forwardLocation: Location? { canGoForward ? history[historyIndex + 1] : nil }

  public func snapshot() -> TabSnapshot? {
    guard let location else { return nil }
    return TabSnapshot(
      location: location, history: history, historyIndex: historyIndex,
      options: tabViewOptions, scope: viewScope, isPinned: isPinned)
  }

  public func restore(_ snapshot: TabSnapshot, fallback: Location) async {
    tabViewOptions = snapshot.options
    viewScope = snapshot.scope
    if await navigate(to: snapshot.location) {
      if snapshot.history.indices.contains(snapshot.historyIndex),
        snapshot.history[snapshot.historyIndex] == snapshot.location
      {
        history = snapshot.history
        historyIndex = snapshot.historyIndex
      }
      isPinned = snapshot.isPinned
    } else {
      await navigate(to: fallback)
      isPinned = false
    }
  }

  public var canGoBack: Bool { historyIndex > 0 }
  public var canGoForward: Bool { historyIndex + 1 < history.count }
  /// The folder above this one. At the root of an archive opened as a folder it is the folder that
  /// holds the archive.
  public var parentLocation: Location? {
    guard let location else { return nil }
    return location.parent ?? registry.container(of: location.providerID)
  }
  public var canGoUp: Bool { parentLocation != nil }
  public var selectedEntries: [FileEntry] { visibleEntries.filter { selection.contains($0.id) } }
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

  // MARK: Selection (never changes the browsing location)

  public func selectAll() { selection = Set(visibleEntries.map(\.id)) }
  public func deselectAll() { selection = [] }
  public func invertSelection() {
    selection = SelectionOps.invert(all: visibleEntries, selected: selection)
  }
  public func quickSelectPreview(_ criteria: QuickSelectCriteria) -> Int {
    criteria.preview(entries: visibleEntries, current: selection).resulting.count
  }
  public func applyQuickSelect(_ criteria: QuickSelectCriteria) {
    selection = criteria.preview(entries: visibleEntries, current: selection).resulting
  }

  // MARK: Refresh

  /// After a connection's text encoding changed: the same server paths, read under the new one.
  /// A path that cannot be rebuilt falls back to `fallback`. Call `refresh()` afterwards.
  public func recodeLocations(providerID: String, fallback: String, _ recode: (String) -> String?)
  {
    func convert(_ location: Location) -> Location {
      guard location.providerID == providerID else { return location }
      return Location(providerID: providerID, path: recode(location.path) ?? fallback)
    }
    guard location?.providerID == providerID else { return }
    history = history.map(convert)
    location = location.map(convert)
    selection = []
  }

  /// Re-lists the current folder (e.g. after changes made by another app), keeping the selection
  /// for items that still exist.
  @discardableResult public func refresh() async -> Bool {
    guard let location else { return false }
    let loaded = await load(location, historyIndex: nil, refreshing: true)
    // Search results may refer to nested folders, not the folder just re-listed.
    if loaded, let scope = searchScope {
      let token = searchToken
      var updated: [FileEntry] = []
      for entry in scope.results {
        let provider = registry.provider(for: entry.location.providerID)
        let fresh = try? await provider?.stat(entry.location)
        updated.append(fresh ?? entry)
      }
      if token == searchToken, var current = searchScope {
        current.results = updated
        searchScope = current
      }
    }
    return loaded
  }

  // MARK: Search (a separate result scope; the folder underneath is untouched)

  /// Searches `root`, or else the open scope's root or the current folder.
  public func search(_ query: SearchQuery, root requestedRoot: Location? = nil) async {
    guard let root = requestedRoot ?? searchScope?.root ?? location else { return }
    searchTask?.cancel()
    if searchScope == nil { folderSelection = selection }
    var scope = SearchScope(query: query, root: root)
    scope.isRunning = !query.isEmpty
    searchScope = scope
    selection = []
    guard !query.isEmpty else { return }
    let scopeRoot = scope.root
    let token = UUID()
    searchToken = token
    let task = Task { [registry, spotlightRunner] in
      do {
        let results: [FileEntry]
        if query.engine == .spotlight, query.engine.isAvailable(for: scopeRoot) {
          guard let spotlightRunner else { throw FileSystemError.unsupportedOperation }
          results = try await spotlightRunner(query, scopeRoot)
        } else {
          guard let provider = registry.provider(for: scopeRoot.providerID) else {
            throw FileSystemError.unsupportedOperation
          }
          results = try await BuiltInSearch.run(query, in: scopeRoot, provider: provider)
        }
        try Task.checkCancellation()
        await MainActor.run { [self] in finishSearch(token, results: results, error: nil) }
      } catch is CancellationError {
      } catch {
        await MainActor.run { [self] in finishSearch(token, results: [], error: error) }
      }
    }
    searchTask = task
    await task.value
  }

  @ObservationIgnored private var searchToken = UUID()

  private func finishSearch(_ token: UUID, results: [FileEntry], error: (any Error)?) {
    guard token == searchToken, var scope = searchScope else { return }
    scope.results = results
    scope.isRunning = false
    scope.errorMessage = error?.localizedDescription
    searchScope = scope
  }

  /// Closes the result scope and returns to the folder listing.
  public func closeSearch() {
    guard searchScope != nil else { return }
    searchTask?.cancel()
    searchToken = UUID()
    searchScope = nil
    let existing = Set(entries.map(\.id))
    selection = folderSelection.intersection(existing)
    folderSelection = []
  }

  public func cancelPendingNavigation() {
    navigationRevision = UUID()
    isLoading = false
  }

  private func load(
    _ destination: Location, historyIndex newIndex: Int?, refreshing: Bool = false
  ) async -> Bool {
    let request = UUID()
    navigationRevision = request
    isLoading = true
    errorMessage = nil
    deniedLocation = nil
    do {
      guard let provider = registry.provider(for: destination.providerID) else {
        throw FileSystemError.unsupportedOperation
      }
      let listing = try await provider.list(
        destination, includeHidden: viewPreferences.showHidden)
      try Task.checkCancellation()
      guard navigationRevision == request else { return false }
      calculatedSizes = [:]
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
      if refreshing {
        let existing = Set(entries.map(\.id))
        if let scope = searchScope {
          selection = selection.intersection(Set(scope.results.map(\.id)))
        } else {
          selection = selection.intersection(existing)
        }
        folderSelection = folderSelection.intersection(existing)
      } else {
        closeSearch()
        selection = []
        folderSelection = []
      }
      isLoading = false
      return true
    } catch {
      guard navigationRevision == request else { return false }
      isLoading = false
      if !(error is CancellationError) { errorMessage = error.localizedDescription }
      if error as? FileSystemError == .permissionDenied { deniedLocation = destination }
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
