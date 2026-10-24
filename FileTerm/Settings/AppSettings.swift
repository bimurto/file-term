import Defaults
import Foundation
import Observation

enum SettingsCategory: String, CaseIterable, Identifiable {
  case general = "General"
  case transfers = "Transfers"
  case shortcuts = "Shortcuts"
  case tags = "Tags"
  case tools = "Tools"
  case editing = "Editing"
  case themes = "Themes"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .transfers: "arrow.left.arrow.right"
    case .shortcuts: "keyboard"
    case .tags: "tag"
    case .tools: "wrench.and.screwdriver"
    case .editing: "square.and.pencil"
    case .themes: "paintpalette"
    }
  }
}

enum PlaceholderPanel: String, CaseIterable, Identifiable {
  case preview = "Preview"
  case activities = "Activities"
  case logs = "Logs"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .preview: "sidebar.right"
    case .activities: "arrow.left.arrow.right"
    case .logs: "list.bullet.rectangle"
    }
  }
  var commandID: String { "view.\(rawValue.lowercased())" }
}

@MainActor @Observable final class AppSettings {
  var visiblePanels: Set<String> {
    didSet { Defaults[panelsKey] = visiblePanels }
  }
  var selectedCategory: String {
    didSet { Defaults[categoryKey] = selectedCategory }
  }
  @ObservationIgnored private let panelsKey: Defaults.Key<Set<String>>
  @ObservationIgnored private let categoryKey: Defaults.Key<String>

  init(suite: UserDefaults = .standard) {
    panelsKey = Defaults.Key("visiblePanels", default: [], suite: suite)
    categoryKey = Defaults.Key(
      "settingsCategory", default: SettingsCategory.general.rawValue, suite: suite)
    visiblePanels = Defaults[panelsKey]
    selectedCategory = Defaults[categoryKey]
  }

  func isVisible(_ panel: PlaceholderPanel) -> Bool { visiblePanels.contains(panel.rawValue) }
  func toggle(_ panel: PlaceholderPanel) {
    if isVisible(panel) {
      visiblePanels.remove(panel.rawValue)
    } else {
      visiblePanels.insert(panel.rawValue)
    }
  }
}
