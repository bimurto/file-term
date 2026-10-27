import Foundation
import Observation

public enum PaneID: String, CaseIterable, Codable, Sendable {
  case first, second
  public var opposite: PaneID { self == .first ? .second : .first }
}

public enum PaneLayout: String, CaseIterable, Codable, Sendable {
  case single, vertical, horizontal
}

@MainActor @Observable public final class BrowserModel {
  public private(set) var firstTabs: PaneTabs
  public private(set) var secondTabs: PaneTabs
  public var firstPane: PaneModel { firstTabs.active }
  public var secondPane: PaneModel { secondTabs.active }
  public var activePaneID: PaneID = .first
  public private(set) var layout: PaneLayout = .single
  public private(set) var lastDualLayout: PaneLayout = .vertical
  public var syncBrowsing = false {
    didSet {
      if layout == .single && syncBrowsing { syncBrowsing = false }
      invalidateMirror()
    }
  }
  public var notice: String?
  /// True while the Quick Open sheet is up, so key-window gating can treat it as part of the browser.
  @ObservationIgnored public var isQuickOpenOpen = false
  @ObservationIgnored public var onVisit: ((Location) -> Void)?
  @ObservationIgnored private var coordinationID = UUID()
  @ObservationIgnored private var pendingMirror: PaneModel?

  public init(registry: ProviderRegistry, viewPreferences: ViewPreferences = ViewPreferences()) {
    firstTabs = PaneTabs(initial: PaneModel(registry: registry, viewPreferences: viewPreferences))
    secondTabs = PaneTabs(initial: PaneModel(registry: registry, viewPreferences: viewPreferences))
  }

  public convenience init(
    providers: [any FileSystemProvider], viewPreferences: ViewPreferences = ViewPreferences()
  ) {
    self.init(registry: ProviderRegistry(providers: providers), viewPreferences: viewPreferences)
  }

  public func tabs(_ id: PaneID) -> PaneTabs { id == .first ? firstTabs : secondTabs }

  public func newTab(in id: PaneID) {
    invalidateMirror()
    tabs(id).newTab()
  }
  public func selectTab(_ tabID: UUID, in id: PaneID) {
    invalidateMirror()
    tabs(id).select(tabID)
  }
  public func selectTab(at index: Int, in id: PaneID) {
    invalidateMirror()
    tabs(id).selectIndex(index)
  }
  public func cycleTab(_ step: Int, in id: PaneID) {
    invalidateMirror()
    tabs(id).cycle(step)
  }
  @discardableResult public func closeTab(_ tabID: UUID? = nil, in id: PaneID) -> Bool {
    invalidateMirror()
    return tabs(id).close(tabID)
  }
  public func closeOtherTabs(in id: PaneID) {
    invalidateMirror()
    tabs(id).closeOthers()
  }

  public func snapshot() -> BrowserSnapshot {
    BrowserSnapshot(
      first: firstTabs.tabs.compactMap { $0.snapshot() },
      second: secondTabs.tabs.compactMap { $0.snapshot() }, firstSelected: firstTabs.selectedIndex,
      secondSelected: secondTabs.selectedIndex, layout: layout, lastDualLayout: lastDualLayout,
      activePane: activePaneID)
  }

  public func restore(_ snapshot: BrowserSnapshot, fallback: Location) async {
    invalidateMirror()
    await firstTabs.restore(snapshot.first, selected: snapshot.firstSelected, fallback: fallback)
    await secondTabs.restore(snapshot.second, selected: snapshot.secondSelected, fallback: fallback)
    lastDualLayout = snapshot.lastDualLayout == .single ? .vertical : snapshot.lastDualLayout
    setLayout(snapshot.layout)
    activePaneID = snapshot.activePane
  }

  private func navigationPane(to destination: Location, in id: PaneID) -> PaneModel {
    let current = pane(id)
    return current.isPinned && current.location != destination
      ? tabs(id).newTab(inheritingView: true) : current
  }

  public func pane(_ id: PaneID) -> PaneModel { id == .first ? firstPane : secondPane }
  public var activePane: PaneModel { pane(activePaneID) }
  public var targetPane: PaneModel? { layout == .single ? nil : pane(activePaneID.opposite) }
  public var canCoordinatePanes: Bool {
    layout != .single && firstPane.location != nil && secondPane.location != nil
      && !firstPane.isLoading && !secondPane.isLoading
  }

  public func setLayout(_ layout: PaneLayout) {
    invalidateMirror()
    self.layout = layout
    if layout == .single { syncBrowsing = false } else { lastDualLayout = layout }
  }

  public func toggleTwoPanes() { setLayout(layout == .single ? lastDualLayout : .single) }

  public func swapPanes() {
    guard canCoordinatePanes else { return }
    invalidateMirror()
    let first = firstTabs
    firstTabs = secondTabs
    secondTabs = first
  }

  public func clonePane() async {
    guard canCoordinatePanes, let location = activePane.location else { return }
    await navigate(to: location, in: activePaneID.opposite)
  }

  @discardableResult public func navigate(to destination: Location, in id: PaneID) async -> Bool {
    invalidateMirror()
    let source = navigationPane(to: destination, in: id)
    let success = await source.navigate(to: destination)
    if success { onVisit?(destination) }
    return success
  }

  public func goBack(in id: PaneID) async {
    invalidateMirror()
    let source = pane(id)
    if source.isPinned, let destination = source.backLocation {
      await navigate(to: destination, in: id)
      return
    }
    if await source.goBack(), let location = source.location { onVisit?(location) }
  }

  public func goForward(in id: PaneID) async {
    invalidateMirror()
    let source = pane(id)
    if source.isPinned, let destination = source.forwardLocation {
      await navigate(to: destination, in: id)
      return
    }
    if await source.goForward(), let location = source.location { onVisit?(location) }
  }

  public func enterFolder(_ destination: Location, in id: PaneID) async {
    let source = pane(id)
    guard destination.parent == source.location else {
      await navigate(to: destination, in: id)
      return
    }
    let child = URL(fileURLWithPath: destination.path).lastPathComponent
    await relativeNavigation(to: destination, in: id, child: child)
  }

  public func goUp(in id: PaneID) async {
    guard let parent = pane(id).location?.parent else { return }
    await relativeNavigation(to: parent, in: id, child: nil)
  }

  public func handleUnmount(at url: URL, home: Location) async {
    let mount = url.standardizedFileURL.path
    for id in PaneID.allCases {
      for tab in tabs(id).tabs {
        guard let location = tab.location, location.providerID == home.providerID,
          location.path == mount || location.path.hasPrefix(mount + "/")
        else { continue }
        invalidateMirror()
        tab.isPinned = false
        let openedHome = await tab.navigate(to: home)
        if openedHome { onVisit?(home) }
        notice =
          openedHome
          ? "The volume at \(mount) was unmounted. Affected tabs were moved to Home."
          : "The volume at \(mount) was unmounted. Home could not be opened."
      }
    }
  }

  /// Moves tabs showing a closed remote connection to Home so no pane keeps a dead listing.
  public func handleDisconnect(providerID: String, home: Location) async {
    for id in PaneID.allCases {
      for tab in tabs(id).tabs {
        guard let location = tab.location, location.providerID == providerID else { continue }
        invalidateMirror()
        tab.isPinned = false
        let openedHome = await tab.navigate(to: home)
        if openedHome { onVisit?(home) }
        notice =
          openedHome
          ? "The connection was closed. Affected tabs were moved to Home."
          : "The connection was closed. Home could not be opened."
      }
    }
  }

  public func dismissNotice() { notice = nil }

  /// Applies the global "Show hidden" toggle and re-lists every open pane.
  public func setShowHidden(_ value: Bool) async {
    firstPane.viewPreferences.showHidden = value
    await refreshAll()
  }

  public func refreshAll() async {
    for id in PaneID.allCases {
      for tab in tabs(id).tabs { await tab.refresh() }
    }
  }

  private func invalidateMirror() {
    coordinationID = UUID()
    pendingMirror?.cancelPendingNavigation()
    pendingMirror = nil
  }

  private func relativeNavigation(to destination: Location, in id: PaneID, child: String?) async {
    invalidateMirror()
    notice = nil
    let token = coordinationID
    let source = navigationPane(to: destination, in: id)
    let target = pane(id.opposite)
    let targetRevision = target.navigationRevision
    let targetLocation = target.location
    let shouldMirror = syncBrowsing && layout != .single && !target.isLoading
    guard await source.navigate(to: destination) else { return }
    onVisit?(destination)
    guard shouldMirror, syncBrowsing, layout != .single, coordinationID == token,
      target.navigationRevision == targetRevision, let targetLocation
    else { return }
    let counterpart: Location?
    if let child {
      counterpart = Location(
        providerID: targetLocation.providerID,
        path: URL(fileURLWithPath: targetLocation.path).appendingPathComponent(child).path)
    } else {
      counterpart = targetLocation.parent
    }
    guard let counterpart else {
      notice = "Sync Browsing: the opposite pane is already at its filesystem root."
      return
    }
    let mirrorTarget = navigationPane(to: counterpart, in: id.opposite)
    pendingMirror = mirrorTarget
    let success = await mirrorTarget.navigate(to: counterpart)
    guard coordinationID == token else { return }
    pendingMirror = nil
    if success {
      onVisit?(counterpart)
    } else {
      notice =
        "Sync Browsing could not open \(counterpart.path). \(mirrorTarget.errorMessage ?? "The folder is unavailable.")"
    }
  }
}
