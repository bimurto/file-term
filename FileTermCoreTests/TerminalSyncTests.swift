import Foundation
import Testing

@testable import FileTermCore

struct TerminalSyncTests {
  private func local(_ path: String) -> Location { Location(providerID: "local", path: path) }

  @Test func waitsForKnownEmptyPromptAndQuotesPaneNavigation() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    #expect(state.paneNavigated(to: local("/a b/it's $(touch nope);`id`")).isEmpty)
    #expect(state.pendingPaneLocation == local("/a b/it's $(touch nope);`id`"))
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [
        .sendCommand("cd -- '/a b/it'\\''s $(touch nope);`id`'\r")
      ])
  }

  @Test func busySuspendsBothDirectionsAndLatestPaneWins() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    #expect(state.shellUpdated(phase: .running, hasPendingInput: false).isEmpty)
    #expect(state.receiveOSC7("file:///terminal").isEmpty)
    #expect(state.paneNavigated(to: local("/first")).isEmpty)
    #expect(state.paneNavigated(to: local("/latest")).isEmpty)
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [
        .sendCommand("cd -- '/latest'\r")
      ])
    #expect(state.receiveOSC7("file:///latest").isEmpty)
    #expect(state.shellUpdated(phase: .idle, hasPendingInput: false).isEmpty)
    #expect(state.pendingPaneLocation == nil)
  }

  @Test func terminalWinsAfterBusyWithoutPaneNavigation() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.shellUpdated(phase: .running, hasPendingInput: false)
    #expect(state.receiveOSC7("file:///terminal%20dir").isEmpty)
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [
        .navigatePane(local("/terminal dir"))
      ])
    #expect(state.paneNavigated(to: local("/terminal dir")).isEmpty)
  }

  @Test func pendingInputNeverGetsOverwrittenOrNavigatesPane() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.shellUpdated(phase: .idle, hasPendingInput: true)
    #expect(state.receiveOSC7("file:///terminal").isEmpty)
    #expect(state.paneNavigated(to: local("/wanted")).isEmpty)
    #expect(state.shellUpdated(phase: .idle, hasPendingInput: true).isEmpty)
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [
        .sendCommand("cd -- '/wanted'\r")
      ])
  }

  @Test func reverseSyncCanBeDisabledWithoutDisablingForwardSync() {
    var state = TerminalSyncState(paneLocation: local("/start"), reverseSyncEnabled: false)
    _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
    #expect(state.receiveOSC7("file:///terminal").isEmpty)
    #expect(state.paneLocation == local("/start"))
    #expect(state.paneNavigated(to: local("/forward")) == [.sendCommand("cd -- '/forward'\r")])
  }

  @Test func unlinkDiscardsQueuedNavigationAndDoesNotReplayOnRelink() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.paneNavigated(to: local("/queued"))
    #expect(state.setLinked(false).isEmpty)
    #expect(state.pendingPaneLocation == nil)
    #expect(state.shellUpdated(phase: .idle, hasPendingInput: false).isEmpty)
    #expect(state.receiveOSC7("file:///terminal").isEmpty)
    #expect(state.setLinked(true) == [.navigatePane(local("/terminal"))])
  }

  @Test func nonlocalPanePausesAndReturningLocalQueuesForwardSync() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
    #expect(state.paneNavigated(to: Location(providerID: "remote", path: "/remote")).isEmpty)
    #expect(state.isPausedForNonlocalLocation)
    #expect(state.receiveOSC7("file:///terminal").isEmpty)
    #expect(state.paneNavigated(to: local("/back")) == [.sendCommand("cd -- '/back'\r")])
  }

  @Test func suppressesBothEchoesAndDuplicateCommands() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
    #expect(state.paneNavigated(to: local("/next")) == [.sendCommand("cd -- '/next'\r")])
    #expect(state.paneNavigated(to: local("/next")).isEmpty)
    #expect(state.receiveOSC7("file:///next").isEmpty)
    #expect(state.shellUpdated(phase: .idle, hasPendingInput: false).isEmpty)
    #expect(state.receiveOSC7("file:///elsewhere") == [.navigatePane(local("/elsewhere"))])
    #expect(state.paneNavigated(to: local("/elsewhere")).isEmpty)
  }

  @Test func emittedCommandReservesShellUntilFreshPromptAndQueuesLatestTarget() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
    #expect(state.paneNavigated(to: local("/first")) == [.sendCommand("cd -- '/first'\r")])
    #expect(state.paneNavigated(to: local("/second")).isEmpty)
    #expect(state.paneNavigated(to: local("/last")).isEmpty)
    #expect(state.receiveOSC7("file:///first").isEmpty)
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [.sendCommand("cd -- '/last'\r")])
  }

  @Test func reverseSyncToggleReconcilesOnlyWhenIdleAndEmpty() {
    var state = TerminalSyncState(paneLocation: local("/start"), reverseSyncEnabled: false)
    _ = state.shellUpdated(phase: .running, hasPendingInput: false)
    _ = state.receiveOSC7("file:///terminal")
    #expect(state.setReverseSyncEnabled(true).isEmpty)
    #expect(state.shellUpdated(phase: .idle, hasPendingInput: true).isEmpty)
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [
        .navigatePane(local("/terminal"))
      ])
  }

  @Test func stateInstancesAreIndependentAndRejectedOSC7DoesNotChangeKnownCWD() {
    var first = TerminalSyncState(paneLocation: local("/start"), localHostnames: ["my-mac"])
    var second = TerminalSyncState(paneLocation: local("/other"))
    _ = first.receiveOSC7("file://my-mac/known")
    #expect(first.receiveOSC7("file://remote/unsafe").isEmpty)
    #expect(first.terminalLocation == local("/known"))
    #expect(second.terminalLocation == nil)
    #expect(second.shellUpdated(phase: .idle, hasPendingInput: false).isEmpty)
    #expect(
      first.shellUpdated(phase: .idle, hasPendingInput: false) == [.navigatePane(local("/known"))])
  }

  @Test func failedCDDoesNotPermanentlySuppressTerminalNavigation() {
    var state = TerminalSyncState(paneLocation: local("/start"))
    _ = state.receiveOSC7("file:///start")
    _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
    _ = state.paneNavigated(to: local("/missing"))
    #expect(
      state.shellUpdated(phase: .idle, hasPendingInput: false) == [.navigatePane(local("/start"))])
  }

  @Test func validatesOSC7AsStrictLocalAbsoluteFileURL() {
    let valid = [
      "file:///tmp/a%20b": "/tmp/a b", "file://localhost/tmp": "/tmp", "file://MY-MAC/tmp": "/tmp",
      "file:///": "/",
    ]
    for (raw, path) in valid {
      #expect(
        TerminalSyncState.localDirectory(fromOSC7: raw, localHostnames: ["my-mac"])
          == URL(fileURLWithPath: path))
    }
    let invalid = [
      "https://localhost/tmp", "file://other-machine/tmp", "file:relative", "/tmp", "",
      "file://user@localhost/tmp", "file://localhost:22/tmp", "file:///tmp?query",
      "file:///tmp#fragment",
      "file:///tmp/%00", "file:///tmp/%1B", "file:///tmp/%0A", "file:///tmp/%0D", "file:///tmp/%7F",
      "file:///tmp/%ZZ", "file:///tmp/%", "file:///tmp/\n", " file:///tmp", "file:///tmp/%FF",
    ]
    for raw in invalid {
      #expect(
        TerminalSyncState.localDirectory(fromOSC7: raw) == nil, "Accepted unsafe OSC7: \(raw)")
    }
  }

  @Test func unsafePanePathsNeverBecomeTerminalInput() {
    for path in ["relative", "/tmp/\nnext", "/tmp/\rnext", "/tmp/\u{1B}next", "/tmp/\0next"] {
      var state = TerminalSyncState(paneLocation: local("/start"))
      _ = state.shellUpdated(phase: .idle, hasPendingInput: false)
      #expect(state.paneNavigated(to: local(path)).isEmpty)
    }
  }

  @Test func shellQuotingProducesOneLiteralArgument() {
    let cases: [(String, String)] = [
      ("", "''"), ("simple", "'simple'"), ("a b", "'a b'"), ("'", "''\\'''"),
      ("a'b'c", "'a'\\''b'\\''c'"), ("$HOME;`id`\\\"*?!", "'$HOME;`id`\\\"*?!'"),
      ("line\nnext\r\t", "'line\nnext\r\t'"), ("日本語/🗂", "'日本語/🗂'"),
    ]
    for (input, expected) in cases {
      #expect(CopyPathFormatter.shellQuoted(input) == expected)
    }
  }
}
