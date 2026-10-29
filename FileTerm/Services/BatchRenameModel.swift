import FileTermCore
import Foundation
import Observation

/// State of the Batch Rename dialog: the items in the order shown in the pane and the rule list.
@MainActor @Observable final class BatchRenameModel: Identifiable {
  let items: [RenameItem]
  var rules: [RenameRule]
  @ObservationIgnored private let now = Date()
  @ObservationIgnored private let submit: ([(location: Location, name: String)]) -> Void

  init(
    items: [RenameItem], rules: [RenameRule] = [RenameRule(kind: .replaceText)],
    submit: @escaping ([(location: Location, name: String)]) -> Void
  ) {
    self.items = items
    self.rules = rules
    self.submit = submit
  }

  nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

  var rows: [RenameRow] { BatchRenamePlanner.preview(items: items, rules: rules, now: now) }
  var changedCount: Int { rows.filter(\.isChanged).count }
  var canRename: Bool { changedCount > 0 }

  func addRule(_ kind: RenameRule.Kind) { rules.append(RenameRule(kind: kind)) }

  func removeRule(_ id: UUID) { rules.removeAll { $0.id == id } }

  func moveRule(_ id: UUID, by offset: Int) {
    guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
    let target = index + offset
    guard rules.indices.contains(target) else { return }
    rules.swapAt(index, target)
  }

  func rename() {
    guard canRename else { return }
    submit(rows.filter(\.isChanged).map { ($0.item.location, $0.proposed) })
  }
}
