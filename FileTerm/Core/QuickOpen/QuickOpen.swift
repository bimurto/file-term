import Foundation

public enum FuzzyMatcher {
  /// Subsequence score; nil when `query` is not a subsequence of `candidate`.
  public static func score(_ query: String, _ candidate: String) -> Int? {
    let q = Array(query.lowercased().filter { !$0.isWhitespace })
    if q.isEmpty { return 0 }
    let c = Array(candidate.lowercased())
    var score = 0
    var qi = 0
    var previous = -2
    for (ci, character) in c.enumerated() where qi < q.count && character == q[qi] {
      score += 1
      if ci == previous + 1 { score += 3 }
      if ci == 0 || !c[ci - 1].isLetter && !c[ci - 1].isNumber { score += 4 }
      previous = ci
      qi += 1
    }
    guard qi == q.count else { return nil }
    if candidate.lowercased().hasPrefix(String(q)) { score += 10 }
    if candidate.lowercased() == String(q) { score += 20 }
    return score - c.count / 8
  }
}

public enum QuickOpenKind: String, Sendable {
  case command, folder, recent, device, favorite, application, renamePreset
}

@MainActor public struct QuickOpenItem: Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let kind: QuickOpenKind
  public let isEnabled: Bool
  public let perform: () -> Void

  public init(
    id: String, title: String, subtitle: String = "", kind: QuickOpenKind, isEnabled: Bool = true,
    perform: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.kind = kind
    self.isEnabled = isEnabled
    self.perform = perform
  }
}

/// Extension point: devices, favorites, applications and rename presets register sources here
/// in later milestones.
@MainActor public protocol QuickOpenSource {
  var items: [QuickOpenItem] { get }
}

@MainActor public struct ClosureQuickOpenSource: QuickOpenSource {
  private let provider: () -> [QuickOpenItem]
  public init(_ provider: @escaping () -> [QuickOpenItem]) { self.provider = provider }
  public var items: [QuickOpenItem] { provider() }
}

@MainActor public enum QuickOpen {
  public static func search(_ query: String, sources: [any QuickOpenSource], limit: Int = 50)
    -> [QuickOpenItem]
  {
    var seen: Set<String> = []
    let all = sources.flatMap(\.items).filter { seen.insert($0.id).inserted }
    if query.trimmingCharacters(in: .whitespaces).isEmpty { return Array(all.prefix(limit)) }
    return all.compactMap { item -> (QuickOpenItem, Int)? in
      guard let score = FuzzyMatcher.score(query, item.title) else { return nil }
      return (item, score + (item.isEnabled ? 0 : -5))
    }
    .sorted { $0.1 > $1.1 }
    .prefix(limit).map(\.0)
  }
}

/// Registration points later milestones fill in (devices M08, favorites M11, applications,
/// rename presets M09). They are empty in M03.
@MainActor public final class QuickOpenExtensionPoints {
  public var devices: [any QuickOpenSource] = []
  public var favorites: [any QuickOpenSource] = []
  public var applications: [any QuickOpenSource] = []
  public var renamePresets: [any QuickOpenSource] = []
  public init() {}
  public var all: [any QuickOpenSource] { devices + favorites + applications + renamePresets }
}
