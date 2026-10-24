import Foundation
import Observation

public struct TabSnapshot: Codable, Sendable {
  public let location: Location
  public let history: [Location]
  public let historyIndex: Int
  public let options: ViewOptions
  public let scope: ViewSettingsScope
  public let isPinned: Bool
}

public struct BrowserSnapshot: Codable, Sendable {
  public let first: [TabSnapshot]
  public let second: [TabSnapshot]
  public let firstSelected: Int
  public let secondSelected: Int
  public let layout: PaneLayout
  public let lastDualLayout: PaneLayout
  public let activePane: PaneID
}

@MainActor @Observable public final class PaneTabs {
  public private(set) var tabs: [PaneModel]
  public private(set) var selectedID: UUID
  public var active: PaneModel { tabs.first { $0.id == selectedID } ?? tabs[0] }
  public var selectedIndex: Int { tabs.firstIndex { $0.id == selectedID } ?? 0 }

  public init(initial: PaneModel) {
    tabs = [initial]
    selectedID = initial.id
  }

  @discardableResult public func newTab() -> PaneModel {
    let pane = active.duplicate()
    tabs.append(pane)
    selectedID = pane.id
    return pane
  }

  public func select(_ id: UUID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    selectedID = id
  }

  public func selectIndex(_ index: Int) {
    guard tabs.indices.contains(index) else { return }
    selectedID = tabs[index].id
  }

  public func cycle(_ step: Int) { selectIndex((selectedIndex + step + tabs.count) % tabs.count) }

  @discardableResult public func close(_ id: UUID? = nil) -> Bool {
    guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == (id ?? selectedID) }) else {
      return false
    }
    let removed = tabs.remove(at: index)
    removed.cancelPendingNavigation()
    if removed.id == selectedID { selectedID = tabs[min(index, tabs.count - 1)].id }
    return true
  }

  public func closeOthers() {
    let current = active
    for pane in tabs where pane !== current { pane.cancelPendingNavigation() }
    tabs = [current]
  }

  public func restore(_ snapshots: [TabSnapshot], selected: Int, fallback: Location) async {
    let template = active
    var restored: [PaneModel] = []
    for snapshot in snapshots {
      let pane = template.duplicate()
      await pane.restore(snapshot, fallback: fallback)
      restored.append(pane)
    }
    if restored.isEmpty {
      await template.navigate(to: fallback)
      restored = [template]
    }
    tabs = restored
    selectedID = tabs[min(max(selected, 0), tabs.count - 1)].id
  }
}
