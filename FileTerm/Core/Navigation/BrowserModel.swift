import Foundation
import Observation

public enum PaneID: String, CaseIterable, Sendable {
  case first, second
  public var opposite: PaneID { self == .first ? .second : .first }
}

public enum PaneLayout: String, CaseIterable, Sendable {
  case single, vertical, horizontal
}

@MainActor @Observable public final class BrowserModel {
  public private(set) var firstPane: PaneModel
  public private(set) var secondPane: PaneModel
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
  @ObservationIgnored public var onVisit: ((Location) -> Void)?
  @ObservationIgnored private var coordinationID = UUID()
  @ObservationIgnored private var pendingMirror: PaneModel?

  public init(providers: [any FileSystemProvider]) {
    firstPane = PaneModel(providers: providers)
    secondPane = PaneModel(providers: providers)
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
    let first = firstPane
    firstPane = secondPane
    secondPane = first
  }

  public func clonePane() async {
    guard canCoordinatePanes, let location = activePane.location else { return }
    await navigate(to: location, in: activePaneID.opposite)
  }

  @discardableResult public func navigate(to destination: Location, in id: PaneID) async -> Bool {
    invalidateMirror()
    let source = pane(id)
    let success = await source.navigate(to: destination)
    if success { onVisit?(destination) }
    return success
  }

  public func goBack(in id: PaneID) async {
    invalidateMirror()
    let source = pane(id)
    if await source.goBack(), let location = source.location { onVisit?(location) }
  }

  public func goForward(in id: PaneID) async {
    invalidateMirror()
    let source = pane(id)
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
      guard let location = pane(id).location, location.providerID == home.providerID,
        location.path == mount || location.path.hasPrefix(mount + "/")
      else { continue }
      let openedHome = await navigate(to: home, in: id)
      notice =
        openedHome
        ? "The volume at \(mount) was unmounted. Affected panes were moved to Home."
        : "The volume at \(mount) was unmounted. Home could not be opened."
    }
  }

  public func dismissNotice() { notice = nil }

  private func invalidateMirror() {
    coordinationID = UUID()
    pendingMirror?.cancelPendingNavigation()
    pendingMirror = nil
  }

  private func relativeNavigation(to destination: Location, in id: PaneID, child: String?) async {
    invalidateMirror()
    notice = nil
    let token = coordinationID
    let source = pane(id)
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
    pendingMirror = target
    let success = await target.navigate(to: counterpart)
    guard coordinationID == token else { return }
    pendingMirror = nil
    if success {
      onVisit?(counterpart)
    } else {
      notice =
        "Sync Browsing could not open \(counterpart.path). \(target.errorMessage ?? "The folder is unavailable.")"
    }
  }
}
