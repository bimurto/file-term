/// How toolbar buttons group, and which groups fold into a dropdown as the window narrows.
public enum ToolbarLayout {
  public enum Group: String, Sendable {
    case navigation, places, layout, viewMode, panels, other
  }

  public enum Segment: Equatable, Sendable {
    case buttons([String])
    case menu(Group, [String])
  }

  /// From everything expanded (0) to everything but navigation in dropdowns (`foldLevels.last`).
  public static let foldLevels = 0...3

  public static func group(for id: String) -> Group {
    switch id {
    case "go.back", "go.forward", "go.enclosingFolder", "go.toFolder": .navigation
    case "go.connect", "go.favorites.manage": .places
    case "view.single", "view.vertical", "view.horizontal": .layout
    case "view.asIcons", "view.asList", "view.asColumns": .viewMode
    case "view.preview", "view.activities", "view.logs", "view.terminal": .panels
    default: .other
    }
  }

  /// Splits `items` into runs of one group, keeping the user's order. A lone button never folds,
  /// except at the last level, where everything outside the named groups shares one More menu.
  public static func segments(for items: [String], foldLevel: Int) -> [Segment] {
    let foldsToMore = foldLevel >= foldLevels.upperBound
    let more =
      foldsToMore ? items.filter { [.places, .other].contains(group(for: $0)) } : []
    var runs: [(group: Group, ids: [String])] = []
    for id in items where !more.contains(id) {
      let current = group(for: id)
      if runs.last?.group == current {
        runs[runs.count - 1].ids.append(id)
      } else {
        runs.append((current, [id]))
      }
    }
    var segments = runs.map { run -> Segment in
      let folds =
        switch run.group {
        case .layout, .viewMode: foldLevel >= 1
        case .panels: foldLevel >= 2
        default: false
        }
      return folds && run.ids.count > 1 ? .menu(run.group, run.ids) : .buttons(run.ids)
    }
    if !more.isEmpty { segments.append(.menu(.other, more)) }
    return segments
  }
}
