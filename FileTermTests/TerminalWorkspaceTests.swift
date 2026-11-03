import AppKit
import Darwin
import FileTermCore
import Foundation
import SwiftUI
import Testing

@testable import FileTerm

@Suite(.serialized)
@MainActor struct TerminalWorkspaceTests {
  @Test func drawerCreatesDistinctSessionsForEachPaneTabAndRetainsThemOnReturn() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    let firstTab = browser.firstPane.id

    #expect(!workspace.panel.isVisible)
    #expect(workspace.currentSession == nil)
    workspace.toggleVisibility()
    let first = try #require(workspace.currentSession)
    try await wait { first.canSendDirectory }
    #expect(directoryMatches(first, fixture.root))

    browser.newTab(in: .first)
    try await wait { workspace.currentSession != nil && workspace.currentSession !== first }
    let nextTab = try #require(workspace.currentSession)
    try await wait { nextTab.canSendDirectory }
    #expect(workspace.linkedPaneTitle == "First pane · Tab 2")
    #expect(first.terminalView.process.running)

    browser.setLayout(.vertical)
    browser.activePaneID = .second
    try await wait {
      workspace.currentSession != nil && workspace.currentSession !== nextTab
        && workspace.currentSession !== first
    }
    let secondPane = try #require(workspace.currentSession)
    try await wait { secondPane.canSendDirectory }
    #expect(workspace.linkedPaneTitle == "Second pane · Tab 1")

    browser.activePaneID = .first
    try await wait { workspace.currentSession === nextTab }
    browser.selectTab(firstTab, in: .first)
    try await wait { workspace.currentSession === first }
    #expect(first.canSendDirectory)
    #expect(nextTab.terminalView.process.running)
    #expect(secondPane.terminalView.process.running)
    #expect(workspace.linkedPaneTitle == "First pane · Tab 1")

    workspace.closeAll()
    try await wait {
      !first.terminalView.process.running && !nextTab.terminalView.process.running
        && !secondPane.terminalView.process.running
    }
  }

  @Test func movingATabToTheOtherPaneKeepsItsRunningSession() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    browser.setLayout(.vertical)
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory }

    browser.moveTabToOtherPane(from: .first)
    try await wait { workspace.linkedPaneTitle == "Second pane · Tab 2" }
    #expect(workspace.currentSession === session)
    #expect(session.terminalView.process.running)
  }

  @Test func closingAnInactiveTabTerminatesOnlyItsOwnedSession() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    let firstTab = browser.firstPane.id
    workspace.toggleVisibility()
    let first = try #require(workspace.currentSession)
    try await wait { first.canSendDirectory }

    browser.newTab(in: .first)
    try await wait { workspace.currentSession != nil && workspace.currentSession !== first }
    let retained = try #require(workspace.currentSession)
    try await wait { retained.canSendDirectory }

    #expect(browser.closeTab(firstTab, in: .first))
    try await wait { first.status == .closed && !first.terminalView.process.running }
    #expect(workspace.currentSession === retained)
    #expect(retained.canSendDirectory)
    #expect(retained.terminalView.process.running)

    workspace.closeAll()
    try await wait { !retained.terminalView.process.running }
  }

  @Test func closingTheSelectedTabReturnsToItsRetainedSibling() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let first = try #require(workspace.currentSession)
    try await wait { first.canSendDirectory }
    browser.newTab(in: .first)
    try await wait { workspace.currentSession != nil && workspace.currentSession !== first }
    let removed = try #require(workspace.currentSession)
    try await wait { removed.canSendDirectory }

    #expect(browser.closeTab(in: .first))
    try await wait {
      workspace.currentSession === first && removed.status == .closed
        && !removed.terminalView.process.running
    }
    #expect(first.canSendDirectory)
    workspace.closeAll()
    try await wait { !first.terminalView.process.running }
  }

  @Test func closeAllIsIdempotentAndObservationCannotRecreateSessions() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory }
    // Leave a tab-change reconciliation queued when closing the window.
    fixture.browser.newTab(in: .first)
    workspace.closeAll()
    workspace.closeAll()
    #expect(workspace.currentSession == nil)
    #expect(session.status == .closed)
    #expect(!session.canSendDirectory)
    try await wait { !session.terminalView.process.running }

    workspace.toggleVisibility()
    workspace.toggleVisibility()
    workspace.followMode = .second
    #expect(workspace.currentSession == nil)
    #expect(session.status == .closed)
  }

  @Test(arguments: ["/bin/zsh", "/bin/bash"])
  func anExitedShellSaysSoAndCanBeReplaced(shell: String) async throws {
    let fixture = try await Fixture.make(shell: shell)
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory }
    #expect(session.sendCommand(" exit"))
    try await wait { !session.terminalView.process.running && workspace.status == "Shell exited" }
    // Typing into the dead terminal must not bring back the busy state.
    session.terminalView.send(source: session.terminalView, data: Array("ls\r".utf8)[...])
    guard case .exited = session.status else {
      Issue.record("Status became \(session.status)")
      return
    }
    #expect(workspace.status == "Shell exited")
    #expect(!session.isBusy)
    workspace.startNewShell()
    let replacement = try #require(workspace.currentSession)
    #expect(replacement !== session)
    try await wait { replacement.canSendDirectory && workspace.status == "Linked" }
    workspace.closeAll()
    try await wait { !replacement.terminalView.process.running }
  }

  @Test func unsupportedShellLaunchesButSynchronizationStaysSafelyPaused() async throws {
    let fixture = try await Fixture.make(shell: "/bin/sh")
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.terminalView.process.running && session.status == .syncPaused }
    #expect(!session.canSendDirectory)
    #expect(!workspace.canSyncNow)
    #expect(workspace.status.hasPrefix("Paused"))
    workspace.syncNow()
    #expect(session.status == .syncPaused)
    #expect(session.directory == nil)
    #expect(!session.hasPendingInput)
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  @Test func changingTheDockKeepsTheTerminalInTheWindow() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: DockHost(workspace: workspace))
    window.orderFront(nil)
    try await wait { session.view.window === window }

    for dock in [TerminalDock.right, .bottom, .right] {
      workspace.panel.dock = dock
      try await Task.sleep(for: .milliseconds(300))
      #expect(session.view.window === window, "Docked \(dock)")
    }
    window.close()
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  /// Rebuilds the split around the panel when the dock changes, as `BrowserView` does.
  private struct DockHost: View {
    let workspace: TerminalWorkspace
    var body: some View {
      if workspace.panel.dock == .right {
        HSplitView {
          Color.clear
          TerminalPanel(workspace: workspace)
        }
      } else {
        VSplitView {
          Color.clear
          TerminalPanel(workspace: workspace)
        }
      }
    }
  }

  @Test func toolbarActionsExplainWhyTheyAreUnavailable() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    #expect(workspace.disabledReason(for: .link) == nil)
    #expect(workspace.disabledReason(for: .clear) != nil)
    #expect(workspace.disabledReason(for: .find) != nil)
    #expect(workspace.disabledReason(for: .reveal) != nil)
    #expect(workspace.disabledReason(for: .openSSH) != nil)

    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory && session.directory != nil }
    #expect(workspace.disabledReason(for: .clear) == nil)
    #expect(workspace.disabledReason(for: .find) == nil)
    #expect(workspace.disabledReason(for: .reveal) == nil)

    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  @Test func findSearchesTheScrollbackInBothDirections() async throws {
    let fixture = try await Fixture.make()
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    session.terminalView.feed(text: "needle one\r\nhay\r\nneedle two\r\n")
    #expect(session.find("needle"))
    #expect(session.find("needle", backward: true))
    #expect(!session.find("absent"))
    #expect(!session.find(""))
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  @Test func sshSessionIsTypedOnlyForAnSFTPPaneAndNeverLetsLocalCdReachIt() async throws {
    let fixture = try await Fixture.make(extraProviders: [RemoteStub(id: "sftp.test")])
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    let browser = fixture.browser
    // Stands in for ssh: records its arguments, then stays running like a remote shell.
    let arguments = fixture.root.appendingPathComponent("arguments.txt")
    let script = fixture.root.appendingPathComponent("fake-ssh")
    try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(arguments.path)'\nexec /bin/sleep 5\n"
      .write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let remoteFolder = "/srv/it's here"
    let command = SSHSessionCommand(
      executable: script.path,
      arguments: ["-t", "--", "host", "cd '/srv/it'\\''s here' && exec \"$SHELL\" -l"])
    workspace.sshSession = { $0.providerID == "sftp.test" ? command : nil }

    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory && workspace.status == "Linked" }
    #expect(!workspace.canOpenSSH)
    #expect(!workspace.showsSFTPFolder)
    workspace.openSSHSession()
    #expect(!session.isBusy)

    let remote = Location(providerID: "sftp.test", path: remoteFolder)
    #expect(await browser.navigate(to: remote, in: .first))
    try await wait { workspace.canOpenSSH && workspace.status == "Paused · SFTP folder" }
    #expect(workspace.showsSFTPFolder)
    workspace.openSSHSession()
    try await wait { FileManager.default.fileExists(atPath: arguments.path) && session.isBusy }
    let received = try String(contentsOf: arguments, encoding: .utf8).split(separator: "\n")
    #expect(received.map(String.init) == command.arguments)
    #expect(!workspace.canOpenSSH)

    // While ssh owns the terminal, moving a pane to a local folder must not type a `cd` into it.
    let elsewhere = fixture.root.appendingPathComponent("elsewhere")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    #expect(await browser.navigate(to: fixture.provider.location(for: elsewhere), in: .first))
    workspace.syncNow()
    try await remainsTrue { session.isBusy && !directoryMatches(session, elsewhere) }
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  @Test(arguments: ["/bin/zsh", "/bin/bash"])
  func linkedNavigationSyncsButPendingInputAndUnlinkedModeDoNotInjectCommands(shell: String)
    async throws
  {
    let fixture = try await Fixture.make(shell: shell, reverseSync: true)
    defer { fixture.cleanup() }
    let workspace = fixture.workspace
    let browser = fixture.browser
    let destination = fixture.root.appendingPathComponent("spaces ' % # é")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    do {
      try await wait { session.canSendDirectory && workspace.status == "Linked" }
    } catch {
      Issue.record(
        "Initial state: status=\(workspace.status), session=\(session.status), cwd=\(session.directory ?? "nil"), pane=\(browser.firstPane.location?.path ?? "nil"), ready=\(session.canSendDirectory), pending=\(session.hasPendingInput)"
      )
      throw error
    }
    #expect(workspace.canSyncNow)

    #expect(await browser.navigate(to: fixture.provider.location(for: destination), in: .first))
    do {
      try await wait {
        session.canSendDirectory && directoryMatches(session, destination)
          && workspace.status == "Linked"
      }
    } catch {
      Issue.record(
        """
        Forward state: status=\(workspace.status), session=\(session.status),
        cwd=\(session.directory ?? "nil"), pane=\(browser.firstPane.location?.path ?? "nil"),
        expected=\(destination.path), canSend=\(session.canSendDirectory),
        pending=\(session.hasPendingInput)
        """
      )
      throw error
    }

    try await remainsTrue {
      directoryMatches(session, destination)
        && browser.firstPane.location == fixture.provider.location(for: destination)
        && workspace.status == "Linked"
    }

    session.insert("echo not submitted")
    try await wait { workspace.status == "Paused · Input pending" }
    #expect(!workspace.canSyncNow)
    #expect(await browser.navigate(to: fixture.provider.location(for: fixture.root), in: .first))
    workspace.syncNow()
    #expect(directoryMatches(session, destination))
    #expect(session.hasPendingInput)
    session.terminalView.send(txt: "\u{15}\r")
    try await wait {
      session.canSendDirectory && directoryMatches(session, fixture.root)
        && workspace.status == "Linked"
    }

    workspace.toggleLinked()
    #expect(!workspace.isLinked)
    #expect(workspace.status == "Unlinked")
    #expect(await browser.navigate(to: fixture.provider.location(for: destination), in: .first))
    // Observation updates the title independently of shell state; explicit sync remains available.
    #expect(directoryMatches(session, fixture.root))
    #expect(workspace.canSyncNow)
    workspace.syncNow()
    try await wait { session.canSendDirectory && directoryMatches(session, destination) }
    #expect(workspace.status == "Unlinked")
    workspace.toggleLinked()
    try await wait { workspace.status == "Linked" }
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  @Test(arguments: ["/bin/zsh", "/bin/bash"])
  func manualCDReverseSyncsOnlyTheOwningInactiveTabWithoutFeedback(shell: String) async throws {
    let fixture = try await Fixture.make(shell: shell, reverseSync: true)
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    let owner = browser.firstPane
    let destination = fixture.root.appendingPathComponent("manual cd ' é")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let expected = fixture.provider.location(for: destination)
    workspace.toggleVisibility()
    let shellSession = try #require(workspace.currentSession)
    try await wait { shellSession.canSendDirectory }

    browser.newTab(in: .first)
    let selected = browser.firstPane
    try await wait {
      workspace.currentSession != nil && workspace.currentSession !== shellSession
    }
    let selectedSession = try #require(workspace.currentSession)
    try await wait { selectedSession.canSendDirectory }
    var visits: [Location] = []
    browser.onVisit = { visits.append($0) }

    shellSession.terminalView.send(txt: "cd -- \(ShellIntegration.quote(destination.path))\r")
    try await wait {
      shellSession.canSendDirectory && directoryMatches(shellSession, destination)
        && owner.location == expected && visits == [expected]
    }
    #expect(browser.firstPane === selected)
    #expect(workspace.currentSession === selectedSession)
    #expect(selected.location == fixture.provider.location(for: fixture.root))
    #expect(directoryMatches(selectedSession, fixture.root))
    try await remainsTrue {
      visits == [expected] && owner.location == expected
        && shellSession.canSendDirectory && directoryMatches(shellSession, destination)
        && browser.firstPane === selected && workspace.currentSession === selectedSession
        && selectedSession.canSendDirectory && directoryMatches(selectedSession, fixture.root)
    }

    browser.selectTab(owner.id, in: .first)
    try await wait { workspace.currentSession === shellSession && workspace.status == "Linked" }
    #expect(visits == [expected])
    workspace.closeAll()
    try await wait {
      !shellSession.terminalView.process.running && !selectedSession.terminalView.process.running
    }
  }

  @Test(arguments: ["/bin/zsh", "/bin/bash"])
  func navigationWhileBusyQueuesOnlyTheLatestFolderWithoutReverseSyncFeedback(shell: String)
    async throws
  {
    let fixture = try await Fixture.make(shell: shell, reverseSync: true)
    defer { fixture.cleanup() }
    let browser = fixture.browser
    let workspace = fixture.workspace
    let intermediate = fixture.root.appendingPathComponent("intermediate")
    let destination = fixture.root.appendingPathComponent("latest ' é")
    for directory in [intermediate, destination] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let intermediateLocation = fixture.provider.location(for: intermediate)
    let expected = fixture.provider.location(for: destination)
    workspace.toggleVisibility()
    let shellSession = try #require(workspace.currentSession)
    try await wait { shellSession.canSendDirectory && workspace.status == "Linked" }
    var visits: [Location] = []
    browser.onVisit = { visits.append($0) }

    shellSession.terminalView.send(txt: "/bin/sleep 5\r")
    try await wait { shellSession.isBusy && workspace.status.hasPrefix("Paused") }
    #expect(!workspace.canSyncNow)
    #expect(await browser.navigate(to: intermediateLocation, in: .first))
    #expect(await browser.navigate(to: expected, in: .first))
    #expect(directoryMatches(shellSession, fixture.root))
    workspace.syncNow()
    #expect(directoryMatches(shellSession, fixture.root))
    try await wait {
      shellSession.canSendDirectory && directoryMatches(shellSession, destination)
        && browser.firstPane.location == expected && workspace.status == "Linked"
    }
    // Only the two explicit browser navigations should be recorded: the old prompt cwd
    // must not reverse-navigate the pane, nor should the generated cd echo back into history.
    let expectedVisits = [intermediateLocation, expected]
    #expect(visits == expectedVisits)
    try await remainsTrue {
      visits == expectedVisits && browser.firstPane.location == expected
        && shellSession.canSendDirectory && directoryMatches(shellSession, destination)
        && workspace.status == "Linked"
    }
    workspace.closeAll()
    try await wait { !shellSession.terminalView.process.running }
  }

  @Test(arguments: ["/bin/zsh", "/bin/bash"], [false, true])
  func delayedReverseNavigationWaitsForIdleAfterNewInput(shell: String, startsCommand: Bool)
    async throws
  {
    let gate = ListingGate()
    let delayedProvider = DelayedLocalProvider(gate: gate)
    let fixture = try await Fixture.make(
      shell: shell, reverseSync: true, browserProvider: delayedProvider)
    defer {
      gate.release()
      fixture.cleanup()
    }
    let browser = fixture.browser
    let workspace = fixture.workspace
    let source = fixture.provider.location(for: fixture.root)
    let destination = fixture.root.appendingPathComponent("delayed reverse")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let expected = fixture.provider.location(for: destination)
    workspace.toggleVisibility()
    let session = try #require(workspace.currentSession)
    try await wait { session.canSendDirectory && workspace.status == "Linked" }
    var visits: [Location] = []
    browser.onVisit = { visits.append($0) }

    gate.destination = expected
    session.terminalView.send(txt: "cd -- \(ShellIntegration.quote(destination.path))\r")
    try await wait { gate.isSuspended && session.canSendDirectory }
    #expect(browser.firstPane.location == source)
    #expect(directoryMatches(session, destination))

    // Latch new input while reverse navigation is suspended inside the provider.
    // Release immediately, without yielding to the workspace's observation task:
    // cancellation must happen synchronously in the terminal state callback.
    session.insert(startsCommand ? "/bin/sleep 5" : "echo not submitted")
    if startsCommand { session.terminalView.send(txt: "\r") }
    #expect(session.hasPendingInput || session.isBusy)
    gate.release()
    try await wait { gate.didReturn && !browser.firstPane.isLoading }
    #expect(gate.wasCancelled)
    try await remainsTrue {
      browser.firstPane.location == source && visits.isEmpty
        && (session.hasPendingInput || session.isBusy)
        && directoryMatches(session, destination)
    }

    if !startsCommand { session.terminalView.send(txt: "\u{15}\r") }
    try await wait {
      session.canSendDirectory && directoryMatches(session, destination)
        && browser.firstPane.location == expected && visits == [expected]
        && workspace.status == "Linked"
    }
    try await remainsTrue {
      session.canSendDirectory && browser.firstPane.location == expected && visits == [expected]
    }
    workspace.closeAll()
    try await wait { !session.terminalView.process.running }
  }

  /// A one-shot listing gate intentionally ignores cancellation until released, as a slow
  /// provider may do. PaneModel must reject its result using the cancelled navigation task.
  @MainActor private final class ListingGate {
    var destination: Location?
    private(set) var isSuspended = false
    private(set) var didReturn = false
    private(set) var wasCancelled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pauseIfNeeded(_ location: Location) async {
      guard destination == location else { return }
      destination = nil
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        isSuspended = true
      }
      wasCancelled = Task.isCancelled
      didReturn = true
    }

    func release() {
      continuation?.resume()
      continuation = nil
    }
  }

  private struct DelayedLocalProvider: FileSystemProvider {
    let id = "local"
    let gate: ListingGate
    private let local = LocalFileSystemProvider()

    func list(_ location: Location) async throws -> [FileEntry] {
      try await list(location, includeHidden: false)
    }

    func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
      let entries = try await local.list(location, includeHidden: includeHidden)
      await gate.pauseIfNeeded(location)
      return entries
    }

    func stat(_ location: Location) async throws -> FileEntry {
      try await local.stat(location)
    }

    func read(_ location: Location) async throws -> any FileByteReader {
      try await local.read(location)
    }

    func write(_ contents: any FileByteReader, to location: Location) async throws {
      try await local.write(contents, to: location)
    }

    func move(_ source: Location, to destination: Location) async throws {
      try await local.move(source, to: destination)
    }

    func delete(_ location: Location) async throws {
      try await local.delete(location)
    }
  }

  /// A server folder that lists nothing; enough for a pane to sit on a non-local location.
  private struct RemoteStub: FileSystemProvider {
    let id: String
    func list(_ location: Location) async throws -> [FileEntry] { [] }
    func stat(_ location: Location) async throws -> FileEntry {
      FileEntry(location: location, name: "stub", kind: .directory)
    }
    func read(_ location: Location) async throws -> any FileByteReader {
      throw FileSystemError.unsupportedOperation
    }
    func write(_ contents: any FileByteReader, to location: Location) async throws {}
    func move(_ source: Location, to destination: Location) async throws {}
    func delete(_ location: Location) async throws {}
  }

  private func directoryMatches(_ session: TerminalSession, _ url: URL) -> Bool {
    guard let path = session.directory else { return false }
    let u1 = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    let u2 = url.resolvingSymlinksInPath()
    return u1.path == u2.path
  }

  /// Check a quiet interval longer than the workspace debounce, rather than assuming
  /// the first matching prompt means no delayed reconciliation can create a feedback loop.
  private func remainsTrue(
    _ predicate: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .milliseconds(400))
    repeat {
      guard predicate() else {
        Issue.record("Terminal workspace did not remain settled", sourceLocation: sourceLocation)
        throw WaitError.unstable
      }
      try await Task.sleep(for: .milliseconds(20))
    } while clock.now < deadline
    #expect(predicate(), sourceLocation: sourceLocation)
  }

  private func wait(
    _ predicate: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(8))
    while !predicate() {
      if clock.now >= deadline {
        Issue.record(
          "Timed out waiting for terminal workspace state", sourceLocation: sourceLocation)
        throw WaitError.timedOut
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  private enum WaitError: Error { case timedOut, unstable }

  /// ShellIntegration captures the environment when the drawer/observed tab creates its PTY.
  /// These overrides are process-wide; this suite's serialization does not isolate other suites.
  /// Until environment injection is available, the test runner must also serialize terminal suites.
  @MainActor private struct Fixture {
    let root: URL
    let suiteName: String
    let suite: UserDefaults
    let provider: LocalFileSystemProvider
    let browser: BrowserModel
    let workspace: TerminalWorkspace
    let oldHome: String?
    let oldZdotdir: String?

    static func make(
      shell: String = "/bin/zsh", reverseSync: Bool = false,
      browserProvider: (any FileSystemProvider)? = nil,
      extraProviders: [any FileSystemProvider] = []
    ) async throws -> Fixture {
      _ = NSApplication.shared
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("fileterm-workspace-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
      let physicalPath = try #require(realpath(temporary.path, nil))
      let root = URL(fileURLWithPath: String(cString: physicalPath)).standardizedFileURL
      free(physicalPath)
      let suiteName = "com.fileterm.tests.\(UUID().uuidString)"
      let suite = try #require(UserDefaults(suiteName: suiteName))
      let settings = AppSettings(suite: suite)
      settings.terminal.shellPath = shell
      settings.terminal.loginShell = false
      settings.terminal.interactiveShell = true
      settings.terminal.integrationEnabled = true
      settings.terminal.followMode = .active
      settings.terminal.reverseSync = reverseSync
      let provider = LocalFileSystemProvider()
      let browser = BrowserModel(providers: [browserProvider ?? provider] + extraProviders)
      #expect(await browser.navigate(to: provider.location(for: root), in: .first))
      #expect(await browser.navigate(to: provider.location(for: root), in: .second))
      let oldHome = getenv("HOME").map { String(cString: $0) }
      let oldZdotdir = getenv("ZDOTDIR").map { String(cString: $0) }
      setenv("HOME", root.path, 1)
      setenv("ZDOTDIR", root.path, 1)
      return Fixture(
        root: root, suiteName: suiteName, suite: suite, provider: provider, browser: browser,
        workspace: TerminalWorkspace(browser: browser, settings: settings),
        oldHome: oldHome, oldZdotdir: oldZdotdir)
    }

    func cleanup() {
      workspace.closeAll()
      if let oldHome { setenv("HOME", oldHome, 1) } else { unsetenv("HOME") }
      if let oldZdotdir { setenv("ZDOTDIR", oldZdotdir, 1) } else { unsetenv("ZDOTDIR") }
      suite.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: root)
    }
  }
}
