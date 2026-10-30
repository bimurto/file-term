import Foundation
import Observation

public enum FileViewMode: String, CaseIterable, Codable, Sendable {
  case icons = "Icons"
  case list = "List"
  case columns = "Columns"
}

public enum ViewSettingsScope: String, CaseIterable, Codable, Sendable {
  case tab = "This Tab"
  case folder = "This Folder"
}

public enum FileSortField: String, CaseIterable, Codable, Sendable {
  case name = "Name"
  case kind = "Kind"
  case added = "Date Added"
  case modified = "Date Modified"
  case opened = "Date Last Opened"
  case created = "Date Created"
  case size = "Size"
  case tags = "Tags"
  case owner = "Owner"
  case group = "Group"
  case permissions = "Permissions"
}

public enum FileGroupField: String, CaseIterable, Codable, Sendable {
  case none = "None"
  case kind = "Kind"
  case added = "Date Added"
  case modified = "Date Modified"
  case opened = "Date Last Opened"
  case created = "Date Created"
  case size = "Size"
  case tags = "Tags"
}

public struct ViewOptions: Codable, Equatable, Sendable {
  public var mode: FileViewMode = .list
  public var sortField: FileSortField = .name
  public var descending = false
  public var groupField: FileGroupField = .none
  /// Optional so settings saved before this option existed still decode.
  private var iconSizeLabel: Bool?
  public var showsIconSize: Bool {
    get { iconSizeLabel ?? false }
    set { iconSizeLabel = newValue }
  }
  public init() {}
  public var order: EntryOrder {
    EntryOrder(field: sortField, order: descending ? .reverse : .forward)
  }
}

@MainActor @Observable public final class ViewPreferences {
  public var defaults = ViewOptions() { didSet { onChange?() } }
  public var folders: [Location: ViewOptions] = [:] { didSet { onChange?() } }
  /// Shared by every pane/tab; separate from any sync "hidden items" option (M09).
  public var showHidden = false
  @ObservationIgnored public var onChange: (() -> Void)?
  public init() {}
}

public struct EntryOrder: SortComparator, Sendable {
  public var field: FileSortField
  public var order: SortOrder
  public init(field: FileSortField, order: SortOrder = .forward) {
    self.field = field
    self.order = order
  }

  public func compare(_ lhs: FileEntry, _ rhs: FileEntry) -> ComparisonResult {
    if (lhs.kind == .directory) != (rhs.kind == .directory) {
      return lhs.kind == .directory ? .orderedAscending : .orderedDescending
    }
    let comparison: ComparisonResult
    switch field {
    case .name: comparison = text(lhs.name, rhs.name)
    case .kind: comparison = text(lhs.kindLabel, rhs.kindLabel)
    case .tags:
      comparison = text(
        lhs.tags.isEmpty ? nil : lhs.tags.sorted().joined(separator: ","),
        rhs.tags.isEmpty ? nil : rhs.tags.sorted().joined(separator: ","))
    case .owner: comparison = text(lhs.owner, rhs.owner)
    case .group: comparison = text(lhs.group, rhs.group)
    case .size: comparison = number(lhs.size.map(Double.init), rhs.size.map(Double.init))
    case .permissions:
      comparison = number(lhs.permissions.map(Double.init), rhs.permissions.map(Double.init))
    case .added:
      comparison = number(lhs.addedAt?.timeIntervalSince1970, rhs.addedAt?.timeIntervalSince1970)
    case .modified:
      comparison = number(
        lhs.modifiedAt?.timeIntervalSince1970, rhs.modifiedAt?.timeIntervalSince1970)
    case .opened:
      comparison = number(lhs.openedAt?.timeIntervalSince1970, rhs.openedAt?.timeIntervalSince1970)
    case .created:
      comparison = number(
        lhs.createdAt?.timeIntervalSince1970, rhs.createdAt?.timeIntervalSince1970)
    }
    if comparison != .orderedSame { return comparison }
    let name = lhs.name.localizedStandardCompare(rhs.name)
    if name != .orderedSame { return directed(name) }
    return lhs.location.path.compare(rhs.location.path)
  }

  private func directed(_ value: ComparisonResult) -> ComparisonResult {
    guard order == .reverse else { return value }
    return value == .orderedAscending
      ? .orderedDescending : value == .orderedDescending ? .orderedAscending : .orderedSame
  }

  private func text(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (.none, .none): return .orderedSame
    case (.none, _): return .orderedDescending
    case (_, .none): return .orderedAscending
    case (.some(let lhs), .some(let rhs)): return directed(lhs.localizedStandardCompare(rhs))
    }
  }

  private func number(_ lhs: Double?, _ rhs: Double?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (.none, .none): return .orderedSame
    case (.none, _): return .orderedDescending
    case (_, .none): return .orderedAscending
    case (.some(let lhs), .some(let rhs)):
      return directed(lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame)
    }
  }
}

extension FileEntry {
  public var kindLabel: String {
    switch kind {
    case .directory: return "Folder"
    case .symbolicLink: return "Symbolic Link"
    case .other: return "Other"
    case .file:
      let suffix = (name as NSString).pathExtension
      return suffix.isEmpty ? "File" : suffix.uppercased() + " File"
    }
  }
}

public struct EntryGroup: Identifiable, Sendable {
  public var id: String { title ?? "all" }
  public let title: String?
  public let entries: [FileEntry]
}

public enum EntryGrouping {
  public static func groups(
    _ entries: [FileEntry], by field: FileGroupField, order: EntryOrder,
    now: Date = Date(), calendar: Calendar = .current
  ) -> [EntryGroup] {
    guard field != .none else {
      return [EntryGroup(title: nil, entries: entries.sorted(using: order))]
    }
    var buckets: [String: [FileEntry]] = [:]
    for entry in entries {
      let labels: [String]
      switch field {
      case .none: labels = []
      case .kind: labels = [entry.kindLabel]
      case .tags: labels = entry.tags.isEmpty ? ["No Tags"] : Array(Set(entry.tags))
      case .size:
        if entry.kind == .directory {
          labels = ["Folders"]
        } else if let size = entry.size {
          labels = [
            size == 0
              ? "Empty"
              : size < 1024
                ? "Under 1 KB"
                : size < 1_048_576
                  ? "1 KB–1 MB" : size < 1_073_741_824 ? "1 MB–1 GB" : "1 GB or Larger"
          ]
        } else {
          labels = ["Unknown"]
        }
      case .added, .modified, .opened, .created:
        let date: Date? =
          switch field {
          case .added: entry.addedAt
          case .modified: entry.modifiedAt
          case .opened: entry.openedAt
          default: entry.createdAt
          }
        if let date {
          if calendar.isDate(date, inSameDayAs: now) {
            labels = ["Today"]
          } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
          {
            labels = ["Yesterday"]
          } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            labels = ["This Week"]
          } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            labels = ["This Month"]
          } else {
            labels = ["Older"]
          }
        } else {
          labels = ["Unknown"]
        }
      }
      for label in labels { buckets[label, default: []].append(entry) }
    }
    let sequence =
      field == .size
      ? ["Folders", "Empty", "Under 1 KB", "1 KB–1 MB", "1 MB–1 GB", "1 GB or Larger", "Unknown"]
      : ["Today", "Yesterday", "This Week", "This Month", "Older", "Unknown"]
    let names =
      (field == .kind || field == .tags)
      ? buckets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      : sequence.filter { buckets[$0] != nil }
    return names.map {
      EntryGroup(title: $0, entries: buckets[$0, default: []].sorted(using: order))
    }
  }
}
