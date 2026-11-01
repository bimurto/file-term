import AppKit
import FileTermCore
import SwiftTerm
import XCTest

@testable import FileTerm

@MainActor
private final class CapturingTerminalView: LocalProcessTerminalView {
  var parser = ShellOSCParser()
  var events: [ShellOSCParser.Event] = []
  override func dataReceived(slice: ArraySlice<UInt8>) {
    events += parser.consume(slice)
    super.dataReceived(slice: slice)
  }
}

final class ShellIntegrationTests: XCTestCase {
  func testSessionsInheritTheLoginShellPath() async throws {
    let path = await LoginShellPath.environment()["PATH"]
    let expected = try XCTUnwrap(path)
    let integration = try ShellIntegration(
      shell: "/bin/zsh", login: false, interactive: true, enabled: false)
    defer { integration.cleanup() }
    XCTAssertTrue(integration.environment.contains("PATH=\(expected)"))
  }

  func testOSCParserAcrossEveryByteAndBothTerminators() {
    var parser = ShellOSCParser()
    let stream =
      "hello\u{1b}]7;file://localhost/tmp/a%20b%25%23%C3%A9\u{7}"
      + "\u{1b}]133;A;fileterm=test\u{1b}\\"
    var events: [ShellOSCParser.Event] = []
    for byte in stream.utf8 { events += parser.consume([byte][...]) }
    XCTAssertEqual(events, [.directory("/tmp/a b%#é"), .prompt("A;fileterm=test")])
  }

  func testRejectRemoteMalformedAndControlDirectoryURLs() {
    for value in [
      "file://evil.example/tmp", "file://localhost/tmp/%00", "file://localhost/tmp/%0A",
      "file://localhost/tmp?q=x", "https://localhost/tmp", "file://u@localhost/tmp",
      "file://localhost/tmp/%GG", "file://localhost/tmp/%", "file://localhost/tmp/%FF",
    ] {
      XCTAssertNil(ShellOSCParser.localDirectory(value), value)
    }
  }

  func testOversizedOSCCannotBecomePrompt() {
    var parser = ShellOSCParser()
    let value =
      "\u{1b}]" + String(repeating: "x", count: 20000)
      + "133;A\u{7}\u{1b}]133;C\u{7}"
    XCTAssertEqual(parser.consume(Array(value.utf8)[...]), [.prompt("C")])
  }

  func testOSC52ReadAndWriteNeverReachEmulator() {
    var filter = ClipboardOSCFilter()
    var result: [UInt8] = []
    let stream = "a\u{1b}]52;c;?\u{7}b\u{1b}]52;c;YWJj\u{1b}\\c\u{1b}[31md"
    for byte in stream.utf8 { result += filter.consume([byte][...]) }
    XCTAssertEqual(String(decoding: result, as: UTF8.self), "abc\u{1b}[31md")
  }

  func testOSC52WithLeadingZerosNeverReachesEmulator() {
    for code in ["052", "0052", "000000052"] {
      var filter = ClipboardOSCFilter()
      let stream = "a\u{1b}]\(code);c;?\u{7}b\u{1b}]\(code);c;YWJj\u{1b}\\c"
      var result: [UInt8] = []
      for byte in stream.utf8 { result += filter.consume([byte][...]) }
      XCTAssertEqual(String(decoding: result, as: UTF8.self), "abc", code)
    }
    var eightBit = ClipboardOSCFilter()
    let bytes: [UInt8] = [0x9d, 48, 53, 50, 59, 99, 59, 63, 0x9c]
    XCTAssertTrue(eightBit.consume(bytes[...]).isEmpty)
  }

  func testOtherOSCCodesStillReachEmulator() {
    for code in ["0", "5", "520", "152", "133"] {
      var filter = ClipboardOSCFilter()
      let stream = Array("\u{1b}]\(code);x\u{7}".utf8)
      XCTAssertEqual(filter.consume(stream[...]), stream, code)
    }
  }

  func testOSC52EightBitFormAndUTF8Continuation() {
    var filter = ClipboardOSCFilter()
    let bytes: [UInt8] = [0x9d, 53, 50, 59, 99, 59, 63, 0x9c]
    XCTAssertTrue(filter.consume(bytes[...]).isEmpty)
    let unicode = Array("ÝÜ hello".utf8)
    XCTAssertEqual(filter.consume(unicode[...]), unicode)
  }

  func testPOSIXQuotingRoundTripsWithoutExpansion() throws {
    let text = "a 'quote' $(touch /not-created) ; `echo bad` \\ é\nnext"
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", "printf '%s' " + ShellIntegration.quote(text)]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertEqual(String(decoding: data, as: UTF8.self), text)
  }

  func testTemporaryStartupFilesArePrivateAndRemoved() throws {
    let integration = try ShellIntegration(
      shell: "/bin/zsh", login: true, interactive: true, enabled: true)
    let root = try XCTUnwrap(integration.temporaryDirectory)
    let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: root.appendingPathComponent(".zshenv").path))
    integration.cleanup()
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  @MainActor
  func testRealZshPTYDirectoryQuotingPendingInputAndForegroundSleep() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent("fileterm-test-\(UUID())")
    let destination = root.appendingPathComponent("spaces ' % # é $(echo unsafe)")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/zsh"
    preferences.loginShell = false
    let session = TerminalSession(directory: root.path, preferences: preferences)
    defer { session.close() }
    try await wait { session.canSendDirectory }
    XCTAssertEqual(
      URL(fileURLWithPath: try XCTUnwrap(session.directory)).resolvingSymlinksInPath(),
      root.resolvingSymlinksInPath())
    XCTAssertTrue(session.sendDirectory(destination.path))
    try await wait { session.canSendDirectory && session.directory == destination.path }
    session.insert("echo not submitted")
    XCTAssertTrue(session.hasPendingInput)
    session.terminalView.send(txt: "\u{0c}")
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertTrue(session.hasPendingInput, "Prompt redisplay must not acknowledge edited input")
    XCTAssertFalse(session.sendDirectory(root.path))
    session.terminalView.send(txt: "\u{15}\r")
    try await wait { session.canSendDirectory }
    session.terminalView.send(txt: "precmd() { PS1='dynamic> '; }\r")
    try await wait { session.canSendDirectory }
    session.terminalView.send(txt: "sleep 1\r")
    try await wait { session.isBusy }
    XCTAssertFalse(session.sendDirectory(root.path))
    try await wait { session.canSendDirectory }
    XCTAssertEqual(session.directory, destination.path)
  }

  @MainActor
  func testRealBashPTYCanStartAndChangeDirectory() async throws {
    _ = NSApplication.shared
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/bash"
    preferences.loginShell = false
    let session = TerminalSession(directory: "/", preferences: preferences)
    defer { session.close() }
    try await wait { session.canSendDirectory }
    XCTAssertTrue(session.sendDirectory("/private/tmp"))
    try await wait { session.canSendDirectory && session.directory == "/private/tmp" }
  }

  @MainActor
  func testZshProfileCanChangeZDOTDIRWithoutBypassingIntegration() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-zdot-\(UUID())")
    let alternate = root.appendingPathComponent("alternate")
    try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "ZDOTDIR=\(ShellIntegration.quote(alternate.path))\n"
      .write(to: root.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
    try "precmd() { PS1='dynamic> '; }\n"
      .write(to: alternate.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
    let marker = root.appendingPathComponent("login")
    try "printf yes > \(ShellIntegration.quote(marker.path))\n"
      .write(to: alternate.appendingPathComponent(".zlogin"), atomically: true, encoding: .utf8)
    var environment = ProcessInfo.processInfo.environment
    environment["HOME"] = root.path
    environment["ZDOTDIR"] = root.path
    let integration = try ShellIntegration(
      shell: "/bin/zsh", login: true, interactive: true,
      enabled: true, environment: environment)
    defer { integration.cleanup() }
    let view = CapturingTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
    view.startProcess(
      executable: integration.executable, args: integration.arguments,
      environment: integration.environment, currentDirectory: root.path)
    defer { if view.process.running { view.terminate() } }
    try await wait { view.events.contains(.prompt("B;fileterm=\(integration.token)")) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    view.events.removeAll()
    view.send(txt: "echo test\r")
    try await wait { view.events.contains(.prompt("B;fileterm=\(integration.token)")) }
  }

  @MainActor
  func testCloseEscalatesHUPResistantForegroundJob() async throws {
    _ = NSApplication.shared
    let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-job-\(UUID())")
    defer { try? FileManager.default.removeItem(at: pidFile) }
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/zsh"
    preferences.loginShell = false
    let session = TerminalSession(directory: "/", preferences: preferences)
    defer { session.close() }
    try await wait { session.canSendDirectory }
    let script =
      "trap '' HUP TERM; echo $$ > " + ShellIntegration.quote(pidFile.path)
      + "; while :; do sleep 1; done"
    session.terminalView.send(txt: "/bin/bash -c " + ShellIntegration.quote(script) + "\r")
    try await wait { FileManager.default.fileExists(atPath: pidFile.path) }
    let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let pid = try XCTUnwrap(Int32(text))
    session.close()
    try await wait { kill(pid, 0) != 0 }
  }

  @MainActor
  func testCloseEscalatesPipelineAfterGroupLeaderExits() async throws {
    _ = NSApplication.shared
    let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-pipeline-\(UUID())")
    defer { try? FileManager.default.removeItem(at: pidFile) }
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/bash"
    preferences.loginShell = false
    let session = TerminalSession(directory: "/", preferences: preferences)
    defer { session.close() }
    try await wait { session.canSendDirectory }
    let script =
      "trap '' HUP TERM; echo $$ > " + ShellIntegration.quote(pidFile.path)
      + "; exec /bin/sleep 600"
    session.terminalView.send(
      txt: "/usr/bin/true | /bin/bash -c " + ShellIntegration.quote(script) + "\r")
    try await wait { FileManager.default.fileExists(atPath: pidFile.path) }
    let text = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let survivor = try XCTUnwrap(Int32(text))
    let group = getpgid(survivor)
    XCTAssertNotEqual(group, survivor)
    try await wait { kill(group, 0) != 0 }
    XCTAssertEqual(kill(survivor, 0), 0)
    session.close()
    try await wait { kill(survivor, 0) != 0 }
  }

  @MainActor
  func testBashLoginIsRealAndRunsLogoutFile() async throws {
    _ = NSApplication.shared
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-login-\(UUID())")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let login = home.appendingPathComponent("login")
    let logout = home.appendingPathComponent("logout")
    try "shopt -q login_shell && printf yes > \(ShellIntegration.quote(login.path))\n"
      .write(to: home.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
    try "printf yes > \(ShellIntegration.quote(logout.path))\n"
      .write(to: home.appendingPathComponent(".bash_logout"), atomically: true, encoding: .utf8)
    var environment = ProcessInfo.processInfo.environment
    environment["HOME"] = home.path
    let integration = try ShellIntegration(
      shell: "/bin/bash", login: true, interactive: true,
      enabled: true, environment: environment)
    defer { integration.cleanup() }
    XCTAssertEqual(integration.arguments, ["-l", "-i"])
    let view = SessionTerminalView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 400), options: .default)
    view.startProcess(
      executable: integration.executable, args: integration.arguments,
      environment: integration.environment, currentDirectory: home.path)
    defer { if view.process.running { view.terminate() } }
    try await wait { FileManager.default.fileExists(atPath: login.path) }
    view.send(txt: "exit\r")
    try await wait { !view.process.running }
    XCTAssertTrue(FileManager.default.fileExists(atPath: logout.path))
  }

  @MainActor
  func testUnsupportedIntegrationStillLaunchesButNeverAllowsCD() async throws {
    _ = NSApplication.shared
    var preferences = TerminalPreferences()
    preferences.shellPath = "/bin/zsh"
    preferences.integrationEnabled = false
    let session = TerminalSession(directory: "/", preferences: preferences)
    defer { session.close() }
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(session.terminalView.process.running)
    XCTAssertEqual(session.status, .syncPaused)
    XCTAssertFalse(session.sendDirectory("/private/tmp"))
  }

  @MainActor
  private func wait(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line)
    async throws
  {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTFail("Timed out waiting for PTY state", file: file, line: line)
    throw NSError(domain: "ShellIntegrationTests", code: 1)
  }
}
