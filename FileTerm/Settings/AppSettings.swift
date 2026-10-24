import Defaults
import FileTermCore
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

enum BrowserChrome: String, CaseIterable {
  case pathBar, titleBar, toolbar, devices, deviceInfo
  var title: String {
    switch self {
    case .pathBar: "Path Bar"
    case .titleBar: "Title Bar"
    case .toolbar: "Toolbar"
    case .devices: "Devices"
    case .deviceInfo: "Device Info"
    }
  }
  var commandID: String { "view.\(rawValue)" }
}

@MainActor @Observable final class AppSettings {
  var hiddenChrome: Set<String> {
    didSet { Defaults[chromeKey] = hiddenChrome }
  }
  private(set) var recentFolders: [String] {
    didSet { Defaults[recentKey] = recentFolders }
  }
  @ObservationIgnored private let chromeKey: Defaults.Key<Set<String>>
  @ObservationIgnored private let recentKey: Defaults.Key<[String]>
  var visiblePanels: Set<String> {
    didSet { Defaults[panelsKey] = visiblePanels }
  }
  var selectedCategory: String {
    didSet { Defaults[categoryKey] = selectedCategory }
  }
  @ObservationIgnored private let panelsKey: Defaults.Key<Set<String>>
  @ObservationIgnored private let categoryKey: Defaults.Key<String>

  init(suite: UserDefaults = .standard) {
    chromeKey = Defaults.Key(
      "hiddenChrome", default: [BrowserChrome.deviceInfo.rawValue], suite: suite)
    recentKey = Defaults.Key("recentFolders", default: [], suite: suite)
    hiddenChrome = Defaults[chromeKey]
    recentFolders = Array(Defaults[recentKey].filter { $0.hasPrefix("/") }.prefix(20))
    panelsKey = Defaults.Key("visiblePanels", default: [], suite: suite)
    categoryKey = Defaults.Key(
      "settingsCategory", default: SettingsCategory.general.rawValue, suite: suite)
    visiblePanels = Defaults[panelsKey]
    selectedCategory = Defaults[categoryKey]
  }

  func isVisible(_ chrome: BrowserChrome) -> Bool { !hiddenChrome.contains(chrome.rawValue) }
  func toggle(_ chrome: BrowserChrome) {
    if isVisible(chrome) {
      hiddenChrome.insert(chrome.rawValue)
    } else {
      hiddenChrome.remove(chrome.rawValue)
    }
  }

  func recordVisit(_ location: Location) {
    guard location.providerID == "local", location.path.hasPrefix("/") else { return }
    recentFolders = Array(
      ([location.path] + recentFolders.filter { $0 != location.path }).prefix(20))
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
