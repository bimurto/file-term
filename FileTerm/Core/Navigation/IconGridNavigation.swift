import CoreGraphics
import Foundation

/// Keyboard and rubber-band selection rules for the icon grid. Each group lays out in its own rows.
public enum IconGridNavigation {
  public enum Direction: Sendable { case left, right, up, down }

  /// The item an arrow key lands on. With nothing selected, any arrow starts at the first item;
  /// at an edge the current item stays.
  public static func move(
    from current: Location?, _ direction: Direction, groups: [[Location]], columns: Int
  ) -> Location? {
    let flat = groups.flatMap { $0 }
    guard let current, let flatIndex = flat.firstIndex(of: current) else { return flat.first }
    let columns = max(columns, 1)
    switch direction {
    case .left: return flat[max(flatIndex - 1, 0)]
    case .right: return flat[min(flatIndex + 1, flat.count - 1)]
    case .up, .down:
      guard let groupIndex = groups.firstIndex(where: { $0.contains(current) }),
        let index = groups[groupIndex].firstIndex(of: current)
      else { return current }
      let group = groups[groupIndex]
      let column = index % columns
      if direction == .up {
        if index >= columns { return group[index - columns] }
        guard let previous = groups[..<groupIndex].last(where: { !$0.isEmpty }) else {
          return current
        }
        let lastRow = (previous.count - 1) / columns
        return previous[min(lastRow * columns + column, previous.count - 1)]
      }
      let nextRow = (index / columns + 1) * columns
      if nextRow < group.count { return group[min(nextRow + column, group.count - 1)] }
      guard let next = groups[(groupIndex + 1)...].first(where: { !$0.isEmpty }) else {
        return current
      }
      return next[min(column, next.count - 1)]
    }
  }

  /// The widest row among the laid-out items. The grid is adaptive, so only layout knows this.
  public static func columns(in frames: [Location: CGRect]) -> Int {
    Dictionary(grouping: frames.values) { $0.minY.rounded() }.values.map(\.count).max() ?? 1
  }

  /// The first name starting with what was typed, ignoring case and accents.
  public static func match(_ typed: String, in entries: [FileEntry]) -> Location? {
    let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
    return entries.first { $0.name.range(of: typed, options: options) != nil }?.id
  }

  public static func selection(in rect: CGRect, frames: [Location: CGRect]) -> Set<Location> {
    Set(frames.filter { $0.value.intersects(rect) }.keys)
  }
}

/// Collects the keys of one type-to-select attempt. A pause starts a new one.
public struct TypeSelectBuffer: Sendable {
  private var text = ""
  private var lastKey: Date?
  public static let pause: TimeInterval = 1

  public init() {}

  public mutating func append(_ characters: String, at date: Date = Date()) -> String {
    if let lastKey, date.timeIntervalSince(lastKey) > Self.pause { text = "" }
    lastKey = date
    text += characters
    return text
  }

  public func isTyping(at date: Date = Date()) -> Bool {
    guard let lastKey, !text.isEmpty else { return false }
    return date.timeIntervalSince(lastKey) <= Self.pause
  }
}
