/// Which items the window toolbar shows. The pane layout and view mode commands show as one
/// segmented group each; everything else is one item per command.
public enum ToolbarLayout {
  public enum Group: String, CaseIterable, Sendable {
    case layout, viewMode

    public var itemID: String { "group." + rawValue }
    public var commands: [String] {
      switch self {
      case .layout: ["view.single", "view.vertical", "view.horizontal"]
      case .viewMode: ["view.asIcons", "view.asList", "view.asColumns"]
      }
    }
    public var title: String {
      switch self {
      case .layout: "Pane Layout"
      case .viewMode: "View Mode"
      }
    }

    public init?(itemID: String) {
      guard let group = Self.allCases.first(where: { $0.itemID == itemID }) else { return nil }
      self = group
    }
  }

  public static let search = "search"
  /// The raw values of AppKit's space items, so saved lists can hold them.
  public static let space = "NSToolbarSpaceItem"
  public static let flexibleSpace = "NSToolbarFlexibleSpaceItem"

  /// The item that shows `id`: its group for a layout or view mode command, else `id` itself.
  public static func itemID(for id: String) -> String {
    Group.allCases.first { $0.commands.contains(id) }?.itemID ?? id
  }

  /// Lists saved before the native toolbar name each layout and view mode button. Each group
  /// takes the place of its first button. Spaces may repeat; nothing else does.
  public static func items(from saved: [String]) -> [String] {
    var seen: Set<String> = []
    return saved.map(itemID).filter { id in
      [space, flexibleSpace].contains(id) || seen.insert(id).inserted
    }
  }
}
