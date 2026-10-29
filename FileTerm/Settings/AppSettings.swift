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
  case terminal = "Terminal"

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
    case .terminal: "terminal"
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
  case pathBar, titleBar, toolbar, devices, deviceInfo, sidebar, tabBar, recentFolders
  var title: String {
    switch self {
    case .pathBar: "Path Bar"
    case .titleBar: "Title Bar"
    case .toolbar: "Toolbar"
    case .devices: "Devices"
    case .deviceInfo: "Device Info"
    case .sidebar: "Sidebar"
    case .tabBar: "Tab Bar"
    case .recentFolders: "Recent Folders"
    }
  }
  var commandID: String { "view.\(rawValue)" }
}

@MainActor @Observable final class AppSettings {
  let viewPreferences: ViewPreferences
  var workspace: WorkspacePreferences {
    didSet { Defaults[workspaceKey] = (try? JSONEncoder().encode(workspace)) ?? Data() }
  }
  var terminal: TerminalPreferences {
    didSet { Defaults[terminalKey] = (try? JSONEncoder().encode(terminal)) ?? Data() }
  }
  var transfers: TransferPreferences {
    didSet { Defaults[transfersKey] = (try? JSONEncoder().encode(transfers)) ?? Data() }
  }
  var connections: ConnectionPreferences {
    didSet { Defaults[connectionsKey] = (try? JSONEncoder().encode(connections)) ?? Data() }
  }
  var syncFavorites: [SyncFavorite] {
    didSet { Defaults[syncFavoritesKey] = (try? JSONEncoder().encode(syncFavorites)) ?? Data() }
  }
  var renamePresets: [RenamePreset] {
    didSet { Defaults[renamePresetsKey] = (try? JSONEncoder().encode(renamePresets)) ?? Data() }
  }
  @ObservationIgnored private let renamePresetsKey: Defaults.Key<Data>
  @ObservationIgnored private let syncFavoritesKey: Defaults.Key<Data>
  @ObservationIgnored private let connectionsKey: Defaults.Key<Data>
  @ObservationIgnored private let transfersKey: Defaults.Key<Data>
  @ObservationIgnored private let terminalKey: Defaults.Key<Data>
  var savedWindows: [WindowSnapshot] {
    get { (try? JSONDecoder().decode([WindowSnapshot].self, from: Defaults[sessionKey])) ?? [] }
    set { Defaults[sessionKey] = (try? JSONEncoder().encode(newValue)) ?? Data() }
  }
  @ObservationIgnored private let workspaceKey: Defaults.Key<Data>
  @ObservationIgnored private let viewsKey: Defaults.Key<Data>
  @ObservationIgnored private let sessionKey: Defaults.Key<Data>
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
  var showHidden: Bool {
    didSet {
      Defaults[showHiddenKey] = showHidden
      viewPreferences.showHidden = showHidden
    }
  }
  var autoRefresh: Bool {
    didSet { Defaults[autoRefreshKey] = autoRefresh }
  }
  var handleArchives: Bool {
    didSet { Defaults[handleArchivesKey] = handleArchives }
  }
  var archivesAsFolders: Bool {
    didSet { Defaults[archivesAsFoldersKey] = archivesAsFolders }
  }
  var searchEngine: SearchEngine {
    didSet { Defaults[searchEngineKey] = searchEngine.rawValue }
  }
  var searchIncludeSubfolders: Bool {
    didSet { Defaults[subfoldersKey] = searchIncludeSubfolders }
  }
  var shortcutOverrides: [String: ShortcutOverride] {
    didSet { Defaults[shortcutsKey] = (try? JSONEncoder().encode(shortcutOverrides)) ?? Data() }
  }
  @ObservationIgnored private let showHiddenKey: Defaults.Key<Bool>
  @ObservationIgnored private let autoRefreshKey: Defaults.Key<Bool>
  @ObservationIgnored private let handleArchivesKey: Defaults.Key<Bool>
  @ObservationIgnored private let archivesAsFoldersKey: Defaults.Key<Bool>
  @ObservationIgnored private let searchEngineKey: Defaults.Key<String>
  @ObservationIgnored private let subfoldersKey: Defaults.Key<Bool>
  @ObservationIgnored private let shortcutsKey: Defaults.Key<Data>
  @ObservationIgnored private let panelsKey: Defaults.Key<Set<String>>
  @ObservationIgnored private let categoryKey: Defaults.Key<String>

  init(suite: UserDefaults = .standard) {
    transfersKey = Defaults.Key("transferPreferences", default: Data(), suite: suite)
    transfers =
      (try? JSONDecoder().decode(TransferPreferences.self, from: Defaults[transfersKey]))
      ?? TransferPreferences()
    connectionsKey = Defaults.Key("connectionPreferences", default: Data(), suite: suite)
    connections =
      (try? JSONDecoder().decode(ConnectionPreferences.self, from: Defaults[connectionsKey]))
      ?? ConnectionPreferences()
    syncFavoritesKey = Defaults.Key("syncFavorites", default: Data(), suite: suite)
    syncFavorites =
      (try? JSONDecoder().decode([SyncFavorite].self, from: Defaults[syncFavoritesKey])) ?? []
    renamePresetsKey = Defaults.Key("renamePresets", default: Data(), suite: suite)
    renamePresets =
      (try? JSONDecoder().decode([RenamePreset].self, from: Defaults[renamePresetsKey])) ?? []
    terminalKey = Defaults.Key("terminalPreferences", default: Data(), suite: suite)
    terminal =
      (try? JSONDecoder().decode(TerminalPreferences.self, from: Defaults[terminalKey]))
      ?? TerminalPreferences()
    workspaceKey = Defaults.Key("workspace", default: Data(), suite: suite)
    viewsKey = Defaults.Key("viewPreferences", default: Data(), suite: suite)
    sessionKey = Defaults.Key("windowSession", default: Data(), suite: suite)
    workspace =
      (try? JSONDecoder().decode(WorkspacePreferences.self, from: Defaults[workspaceKey]))
      ?? WorkspacePreferences()
    viewPreferences = ViewPreferences()
    if let snapshot = try? JSONDecoder().decode(
      ViewPreferenceSnapshot.self, from: Defaults[viewsKey])
    {
      viewPreferences.defaults = snapshot.defaults
      viewPreferences.folders = snapshot.folders
    }
    chromeKey = Defaults.Key(
      "hiddenChrome", default: [BrowserChrome.deviceInfo.rawValue], suite: suite)
    recentKey = Defaults.Key("recentFolders", default: [], suite: suite)
    hiddenChrome = Defaults[chromeKey]
    recentFolders = Array(Defaults[recentKey].filter { $0.hasPrefix("/") }.prefix(20))
    panelsKey = Defaults.Key("visiblePanels", default: [], suite: suite)
    categoryKey = Defaults.Key(
      "settingsCategory", default: SettingsCategory.general.rawValue, suite: suite)
    visiblePanels = Defaults[panelsKey]
    showHiddenKey = Defaults.Key("showHidden", default: false, suite: suite)
    autoRefreshKey = Defaults.Key("autoRefresh", default: false, suite: suite)
    handleArchivesKey = Defaults.Key("handleArchives", default: true, suite: suite)
    archivesAsFoldersKey = Defaults.Key("archivesAsFolders", default: false, suite: suite)
    searchEngineKey = Defaults.Key(
      "searchEngine", default: SearchEngine.builtIn.rawValue, suite: suite)
    subfoldersKey = Defaults.Key("searchSubfolders", default: true, suite: suite)
    shortcutsKey = Defaults.Key("shortcutOverrides", default: Data(), suite: suite)
    showHidden = Defaults[showHiddenKey]
    autoRefresh = Defaults[autoRefreshKey]
    handleArchives = Defaults[handleArchivesKey]
    archivesAsFolders = Defaults[archivesAsFoldersKey]
    searchEngine = SearchEngine(rawValue: Defaults[searchEngineKey]) ?? .builtIn
    searchIncludeSubfolders = Defaults[subfoldersKey]
    shortcutOverrides =
      (try? JSONDecoder().decode([String: ShortcutOverride].self, from: Defaults[shortcutsKey]))
      ?? [:]
    selectedCategory = Defaults[categoryKey]
    viewPreferences.showHidden = showHidden
    viewPreferences.onChange = { [weak self] in
      guard let self else { return }
      let snapshot = ViewPreferenceSnapshot(
        defaults: viewPreferences.defaults, folders: viewPreferences.folders)
      Defaults[viewsKey] = (try? JSONEncoder().encode(snapshot)) ?? Data()
    }
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
