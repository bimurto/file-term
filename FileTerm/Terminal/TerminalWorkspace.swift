import AppKit
import FileTermCore
import Observation

/// The `ssh` command that opens a shell on the host behind a connected pane.
struct SSHSessionCommand: Equatable {
  let executable: String
  let arguments: [String]
}

/// A window owns the workspace; a pane-tab identity owns each process, even while offscreen.
@MainActor @Observable final class TerminalWorkspace {
  var panel: TerminalPanelState
  private(set) var currentSession: TerminalSession?
  private(set) var linkedPaneTitle = "No pane"
  private(set) var status = "Terminal hidden"

  var followMode: TerminalFollowMode {
    get { settings.terminal.followMode }
    set {
      settings.terminal.followMode = newValue
      if newValue == .unlinked {
        for record in records.values { record.reverseTask?.cancel() }
      }
      refresh()
    }
  }
  var reverseSync: Bool {
    get { settings.terminal.reverseSync }
    set {
      settings.terminal.reverseSync = newValue
      if !newValue {
        for record in records.values { record.reverseTask?.cancel() }
      }
      refresh()
    }
  }
  var isLinked: Bool { followMode != .unlinked }
  var canSyncNow: Bool {
    guard let record = currentRecord, let location = record.pane.location else { return false }
    return record.session.canSendDirectory
      && record.pane.searchScope == nil && location.providerID == "local"
      && Self.existingDirectory(location.path)
  }

  /// Set by the window: the ssh command for a pane location, or nil when it has none (M08.03).
  @ObservationIgnored var sshSession: @MainActor (Location) -> SSHSessionCommand? = { _ in nil }

  var canOpenSSH: Bool {
    guard let record = currentRecord, let location = record.pane.location else { return false }
    return record.session.canSendDirectory && record.pane.searchScope == nil
      && sshSession(location) != nil
  }

  @ObservationIgnored private let browser: BrowserModel
  @ObservationIgnored private let settings: AppSettings
  @ObservationIgnored private var records: [UUID: Record] = [:]
  @ObservationIgnored private var currentID: UUID?
  @ObservationIgnored private var debounce: Task<Void, Never>?
  @ObservationIgnored private weak var previousResponder: NSResponder?
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var lastLinkedMode: TerminalFollowMode = .active

  @MainActor private final class Record {
    let pane: PaneModel
    let session: TerminalSession
    var sync: TerminalSyncState
    var reverseTask: Task<Void, Never>?
    var reverseDestination: Location?
    var reverseSource: Location?
    var reverseInFlight = false
    var appearance: TerminalPreferences?

    init(pane: PaneModel, session: TerminalSession, preferences: TerminalPreferences) {
      self.pane = pane
      self.session = session
      sync = TerminalSyncState(
        paneLocation: pane.location ?? Location(providerID: "local", path: NSHomeDirectory()),
        isLinked: preferences.followMode != .unlinked,
        reverseSyncEnabled: preferences.reverseSync)
    }
  }

  private var currentRecord: Record? { currentID.flatMap { records[$0] } }

  init(browser: BrowserModel, settings: AppSettings, panel: TerminalPanelState? = nil) {
    self.browser = browser
    self.settings = settings
    self.panel = panel ?? TerminalPanelState()
    refresh()
    observe()
  }

  func toggleVisibility() {
    panel.isVisible.toggle()
    if panel.isVisible { refresh() } else { restorePaneFocus() }
  }

  func toggleFocus() {
    if let view = currentSession?.view, let window = view.window,
      let responder = window.firstResponder as? NSView,
      responder === view || responder.isDescendant(of: view)
    {
      restorePaneFocus()
      return
    }
    previousResponder = NSApp.keyWindow?.firstResponder
    panel.isVisible = true
    refresh()
    // Allow SwiftUI to attach the retained AppKit view before requesting first responder.
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.currentSession?.focus()
    }
  }

  func toggleLinked() {
    if isLinked {
      lastLinkedMode = followMode
      followMode = .unlinked
    } else {
      followMode = lastLinkedMode
    }
  }

  func syncNow() {
    guard canSyncNow, let record = currentRecord, let path = record.pane.location?.path else {
      return
    }
    // Explicit synchronization works when unlinked too, but never submits over typed input.
    record.session.sendDirectory(path)
    updateStatus()
  }

  func revealDirectory() {
    guard let record = currentRecord, let path = record.session.directory,
      Self.existingDirectory(path)
    else { return }
    let destination = Location(providerID: "local", path: path)
    let target = isLinked ? record.pane : browser.activePane
    navigate(destination, owning: target)
  }

  /// Types an explicit `ssh` command for the connected SFTP host and folder into the local
  /// shell. ssh asks for any password itself. Only an idle shell is given the command, and folder
  /// sync stays paused for the remote pane, so no local `cd` ever reaches the remote shell.
  func openSSHSession() {
    guard canOpenSSH, let record = currentRecord, let location = record.pane.location,
      let command = sshSession(location)
    else { return }
    let words = [command.executable] + command.arguments
    let line = " " + words.map(record.session.quotePath).joined(separator: " ")
    record.session.sendCommand(line)
    updateStatus()
  }

  func insertSelection() {
    let paths = browser.activePane.selectedEntries
      .filter { $0.location.providerID == "local" }.map { $0.location.path }
    guard !paths.isEmpty else { return }
    panel.isVisible = true
    refresh()
    if let session = currentSession {
      session.insert(paths.map(session.quotePath).joined(separator: " ") + " ")
    }
  }

  func perform(command: String) {
    switch command {
    case "view.terminal", "terminal.toggle", "terminal.toggleVisibility": toggleVisibility()
    case "terminal.focus", "terminal.toggleFocus": toggleFocus()
    case "link", "terminal.link", "terminal.toggleLinked": toggleLinked()
    case "reverseSync", "terminal.reverseSync": reverseSync.toggle()
    case "dock", "terminal.dock": panel.dock = panel.dock == .bottom ? .right : .bottom
    case "followActive", "terminal.followActive": followMode = .active
    case "followFirst", "terminal.followFirst": followMode = .first
    case "followSecond", "terminal.followSecond": followMode = .second
    case "sync", "terminal.sync", "terminal.syncNow": syncNow()
    case "reveal", "terminal.reveal", "terminal.revealDirectory": revealDirectory()
    case "insertSelection", "terminal.insertSelection": insertSelection()
    case "openSSH", "terminal.openSSH": openSSHSession()
    case "clear", "terminal.clear": currentSession?.clear()
    case "find", "terminal.find": find()
    case "terminal.dockBottom": panel.dock = .bottom
    case "terminal.dockRight": panel.dock = .right
    case "close", "terminal.close": closePanel()
    default: break
    }
  }

  func closeAll() {
    closed = true
    debounce?.cancel()
    debounce = nil
    terminateSessions()
  }

  func closePanel() {
    panel.isVisible = false
    restorePaneFocus()
    terminateSessions()
    updateStatus()
  }

  private func terminateSessions() {
    for record in records.values {
      record.session.onDirectory = nil
      record.session.onReady = nil
      record.reverseTask?.cancel()
      record.session.close()
    }
    records.removeAll()
    currentSession = nil
    currentID = nil
  }

  private func find() {
    guard let session = currentSession else { return }
    let alert = NSAlert()
    alert.messageText = "Find in Terminal"
    alert.addButton(withTitle: "Find Next")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.placeholderString = "Search scrollback"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn { _ = session.find(field.stringValue) }
  }

  private func restorePaneFocus() {
    if let view = previousResponder as? NSView, let window = view.window,
      window.makeFirstResponder(view)
    {
      return
    }
    guard let window = currentSession?.view.window ?? NSApp.keyWindow,
      let content = window.contentView
    else { return }
    let terminalView = currentSession?.view
    func paneResponders(in view: NSView) -> [NSView] {
      if view === terminalView { return [] }
      if view is NSTableView { return [view] }
      return view.subviews.flatMap { paneResponders(in: $0) }
    }
    func owningPane(in view: NSView) -> NSView? {
      if view.accessibilityIdentifier() == "pane.\(browser.activePaneID.rawValue)" { return view }
      return view.subviews.lazy.compactMap { owningPane(in: $0) }.first
    }
    let paneRoot = owningPane(in: content)
    let candidates = paneResponders(in: paneRoot ?? content)
    let index =
      paneRoot == nil && browser.layout != .single && browser.activePaneID == .second ? 1 : 0
    if !candidates.isEmpty {
      window.makeFirstResponder(candidates[min(index, candidates.count - 1)])
    } else {
      // Icon/column layouts may not expose a native table responder.
      window.makeFirstResponder(content)
    }
  }

  /// Re-arm immediately, not after the debounce: navigation during a running command must not
  /// disappear between the one-shot Observation callback and the eventual reconciliation.
  private func observe() {
    guard !closed else { return }
    withObservationTracking {
      _ = browser.activePaneID
      _ = browser.layout
      _ = settings.terminal
      for side in PaneID.allCases {
        _ = browser.tabs(side).selectedID
        for pane in browser.tabs(side).tabs {
          _ = pane.location
          _ = pane.isLoading
          _ = pane.searchScope
          _ = pane.isPinned
        }
      }
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, !self.closed else { return }
        self.observe()
        for record in self.records.values
        where !self.isLinked || !self.reverseSync || record.pane.searchScope != nil {
          record.reverseTask?.cancel()
        }
        self.debounce?.cancel()
        self.debounce = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .milliseconds(150))
          guard !Task.isCancelled else { return }
          self?.refresh()
        }
      }
    }
  }

  private func refresh() {
    guard !closed else { return }
    let allPanes = PaneID.allCases.flatMap { browser.tabs($0).tabs }
    let liveIDs = Set(allPanes.map(\.id))
    for id in Array(records.keys) where !liveIDs.contains(id) {
      let removed = records.removeValue(forKey: id)
      removed?.session.onDirectory = nil
      removed?.session.onReady = nil
      removed?.reverseTask?.cancel()
      removed?.session.close()
    }
    if let id = currentID, !liveIDs.contains(id) { currentID = nil }

    let target: PaneModel
    if followMode == .unlinked, let id = currentID,
      let retained = allPanes.first(where: { $0.id == id })
    {
      target = retained
    } else {
      switch followMode {
      case .first: target = browser.firstPane
      case .second: target = browser.secondPane
      case .active, .unlinked: target = browser.activePane
      }
    }
    currentID = target.id
    // Do not spawn any shell until the drawer is first opened.
    if panel.isVisible, records[target.id] == nil { createSession(for: target) }
    currentSession = records[target.id]?.session
    for (id, record) in records {
      if record.appearance != settings.terminal {
        record.session.applyAppearance(settings.terminal)
        record.appearance = settings.terminal
      }
      reconcile(record, id: id)
    }
    updateStatus()
  }

  private func createSession(for pane: PaneModel) {
    let location = pane.location
    let path =
      location?.providerID == "local" && Self.existingDirectory(location?.path ?? "")
      ? location!.path : NSHomeDirectory()
    let session = TerminalSession(directory: path, preferences: settings.terminal)
    let record = Record(pane: pane, session: session, preferences: settings.terminal)
    records[pane.id] = record
    session.onStateChange = { [weak self, weak record] in
      guard let self, let record else { return }
      if record.session.isBusy || record.session.hasPendingInput {
        record.reverseTask?.cancel()
      }
      self.updateStatus()
    }
    session.onRevealPath = { [weak self, weak pane] path in
      guard let self, let pane else { return }
      let url = URL(fileURLWithPath: path)
      let directory = Self.existingDirectory(path) ? url : url.deletingLastPathComponent()
      guard Self.existingDirectory(directory.path) else { return }
      self.navigate(Location(providerID: "local", path: directory.path), owning: pane)
    }
    session.onDirectory = { [weak self, weak session] path in
      guard let self, let session, let record = self.records[pane.id],
        record.session === session, Self.existingDirectory(path)
      else { return }
      // Directory callbacks precede onReady. Stage the cwd while reconciliation is suspended,
      // then let the prompt reconcile the latest pane intent before considering reverse sync.
      _ = record.sync.shellUpdated(phase: .unknown, hasPendingInput: session.hasPendingInput)
      self.reconcile(record, id: pane.id)
      let effects = record.sync.receiveOSC7(
        Self.normalizedShellURL(path, pane: record.pane.location).absoluteString)
      self.apply(effects, record: record, id: pane.id)
      self.updateStatus()
    }
    observeSession(id: pane.id)
    session.onReady = { [weak self, weak session] in
      guard let self, let session, let record = self.records[pane.id],
        record.session === session
      else { return }
      // Sample the pane synchronously: a debounce may still be outstanding at this prompt.
      _ = record.sync.shellUpdated(phase: .unknown, hasPendingInput: session.hasPendingInput)
      self.reconcile(record, id: pane.id)
      let effects = record.sync.shellUpdated(
        phase: session.isBusy ? .running : .idle, hasPendingInput: session.hasPendingInput)
      self.apply(effects, record: record, id: pane.id)
      self.updateStatus()
    }
  }

  private func observeSession(id: UUID) {
    guard !closed, let record = records[id] else { return }
    withObservationTracking {
      _ = record.session.isBusy
      _ = record.session.hasPendingInput
      _ = record.session.status
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, let record = self.records[id], !self.closed else { return }
        self.observeSession(id: id)
        // Only real onReady callbacks may acknowledge command completion with .idle.
        if record.session.isBusy || record.session.hasPendingInput {
          self.reconcile(record, id: id)
        }
        self.updateStatus()
      }
    }
  }

  private func reconcile(_ record: Record, id: UUID) {
    if record.reverseDestination != nil {
      if record.pane.location == record.reverseSource, isLinked, reverseSync {
        applyPendingReverse(record, id: id)
        return
      }
      record.reverseDestination = nil
      record.reverseSource = nil
    }
    if record.session.isBusy || record.session.hasPendingInput {
      apply(
        record.sync.shellUpdated(
          phase: record.session.isBusy ? .running : .unknown,
          hasPendingInput: record.session.hasPendingInput), record: record, id: id)
    }
    let linked = isLinked && record.pane.searchScope == nil
    // Disable first; otherwise a just-unlinked pane navigation could enqueue a cd.
    if !linked { apply(record.sync.setLinked(false), record: record, id: id) }
    if let location = record.pane.location {
      apply(record.sync.paneNavigated(to: location), record: record, id: id)
    }
    apply(record.sync.setReverseSyncEnabled(reverseSync), record: record, id: id)
    if linked && !record.sync.isLinked {
      apply(record.sync.setLinked(true), record: record, id: id)
    }
  }

  private func apply(_ effects: [TerminalSyncState.Effect], record: Record, id: UUID) {
    for effect in effects {
      switch effect {
      case .sendCommand:
        guard !record.session.isBusy, !record.session.hasPendingInput,
          let location = record.pane.location, location.providerID == "local",
          record.pane.searchScope == nil, Self.existingDirectory(location.path)
        else { continue }
        record.session.sendDirectory(location.path)
      case .navigatePane(let location):
        guard Self.existingDirectory(location.path), !record.session.isBusy,
          !record.session.hasPendingInput
        else { continue }
        record.reverseDestination = location
        record.reverseSource = record.pane.location
        applyPendingReverse(record, id: id)
      }
    }
  }

  private func applyPendingReverse(_ record: Record, id: UUID) {
    guard !record.reverseInFlight, let destination = record.reverseDestination,
      record.pane.location == record.reverseSource, !record.pane.isLoading,
      !record.pane.isPinned, record.pane.searchScope == nil,
      record.session.canSendDirectory, isLinked, reverseSync
    else { return }
    record.reverseInFlight = true
    record.reverseTask = Task { @MainActor [weak self, weak record] in
      defer {
        record?.reverseInFlight = false
        record?.reverseTask = nil
      }
      guard let self, let record, self.records[id] === record,
        !Task.isCancelled, record.reverseDestination == destination,
        record.pane.location == record.reverseSource, !record.pane.isLoading,
        self.isLinked, self.reverseSync, !record.pane.isPinned,
        record.pane.searchScope == nil, record.session.canSendDirectory,
        Self.existingDirectory(destination.path)
      else { return }
      // Keep pending intent until navigation completes, so refresh cannot echo the old pane
      // location back into the shell while the directory listing is loading.
      let success: Bool
      if let side = PaneID.allCases.first(where: { self.browser.pane($0).id == id }) {
        success = await self.browser.navigate(to: destination, in: side)
      } else {
        // An inactive tab can navigate itself without changing the selected tab or its history.
        success = await record.pane.navigate(to: destination)
        if success { self.browser.onVisit?(destination) }
      }
      if success, record.reverseDestination == destination {
        record.reverseDestination = nil
        record.reverseSource = nil
      }
      self.updateStatus()
    }
  }

  private func navigate(_ destination: Location, owning pane: PaneModel) {
    Task { @MainActor [weak self, weak pane] in
      guard let self, let pane,
        PaneID.allCases.contains(where: { self.browser.tabs($0).tabs.contains { $0.id == pane.id } }
        )
      else { return }
      if let side = PaneID.allCases.first(where: { self.browser.pane($0).id == pane.id }) {
        _ = await self.browser.navigate(to: destination, in: side)
      } else if !pane.isPinned, await pane.navigate(to: destination) {
        self.browser.onVisit?(destination)
      }
    }
  }

  private func updateStatus() {
    guard let record = currentRecord else {
      linkedPaneTitle = "No terminal session"
      status = panel.isVisible ? "Opening terminal…" : "Terminal hidden"
      return
    }
    let side = PaneID.allCases.first { browser.tabs($0).tabs.contains { $0.id == record.pane.id } }
    linkedPaneTitle = side == .second ? "Second pane" : "First pane"
    if let index = side.flatMap({ browser.tabs($0).tabs.firstIndex { $0.id == record.pane.id } }) {
      linkedPaneTitle += " · Tab \(index + 1)"
    }
    if !isLinked {
      status = "Unlinked"
    } else if record.pane.searchScope != nil {
      status = "Paused · Search results"
    } else if let location = record.pane.location, sshSession(location) != nil {
      status = "Paused · SFTP folder"
    } else if record.pane.location?.providerID != "local" {
      status = "Paused · Non-local folder"
    } else if record.session.isBusy {
      status = "Paused · Shell busy or awaiting prompt"
    } else if record.session.hasPendingInput {
      status = "Paused · Input pending"
    } else if record.session.directory.map({
      Self.normalizedShellURL($0, pane: record.pane.location).path
    }) != record.pane.location?.path {
      status = "Out of sync"
    } else {
      status = "Linked"
    }
  }

  /// Match the provider's URL spelling before handing paths to the pure state machine.
  /// In particular bash may report /private/var while the pane uses /var for the same cwd.
  private static func normalizedShellURL(_ path: String, pane: Location?) -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    if let pane, pane.providerID == "local" {
      let paneURL = URL(fileURLWithPath: pane.path)
      if url.resolvingSymlinksInPath() == paneURL.resolvingSymlinksInPath() {
        return paneURL
      }
    }
    return url
  }

  private static func existingDirectory(_ path: String) -> Bool {
    guard path.hasPrefix("/"),
      !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return false }
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &directory)
      && directory.boolValue
  }
}
