import Foundation
import Testing

@testable import FileTermCore

struct LoginShellPathTests {
  private func withShell<T>(_ body: String, _ test: (String) async throws -> T) async throws -> T {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let shell = folder.appendingPathComponent("fake-shell")
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: shell)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
    return try await test(shell.path)
  }

  @Test func parseIgnoresWhatStartupFilesPrint() {
    #expect(
      LoginShellPath.parse("Welcome\n__FILETERM_PATH__/a:/b__FILETERM_PATH__bye\n") == "/a:/b")
    #expect(LoginShellPath.parse("no markers") == nil)
    #expect(LoginShellPath.parse("__FILETERM_PATH____FILETERM_PATH__") == nil)
  }

  @Test func readsThePathTheShellSets() async throws {
    let path = try await withShell(
      """
      echo welcome
      PATH=/custom/bin:/usr/bin:/bin
      export PATH
      exec /bin/sh -c "$2"
      """
    ) { await LoginShellPath.read(shell: $0, timeout: .seconds(10)) }
    #expect(path == "/custom/bin:/usr/bin:/bin")
  }

  @Test func aFailingOrMissingShellFindsNothing() async throws {
    let failing = try await withShell("exit 1") {
      await LoginShellPath.read(shell: $0, timeout: .seconds(10))
    }
    #expect(failing == nil)
    let missing = await LoginShellPath.read(
      shell: "/nonexistent/shell", timeout: .seconds(10))
    #expect(missing == nil)
  }

  @Test func aHangingShellTimesOutEvenWhenAChildKeepsTheOutputOpen() async throws {
    let start = ContinuousClock.now
    let path = try await withShell(
      """
      /bin/sleep 5 &
      wait
      """
    ) { await LoginShellPath.read(shell: $0, timeout: .milliseconds(200)) }
    #expect(path == nil)
    #expect(ContinuousClock.now - start < .seconds(3))
  }

  @Test func theMissingProgramCheckUsesThePathToolsRunWith() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let program = folder.appendingPathComponent("only-here")
    try Data("#!/bin/sh\n".utf8).write(to: program)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
    let check = Prerequisite.commandLineProgram("only-here")
    #expect(Prerequisites.live(path: folder.path).missing(check) == nil)
    #expect(Prerequisites.live(path: "/usr/bin").missing(check) != nil)

    let path = try #require(await LoginShellPath.environment()["PATH"])
    #expect(Prerequisites.live.searchPath == path.split(separator: ":").map(String.init))
  }

  @Test func theRealLookupKeepsSystemFolders() async {
    let environment = await LoginShellPath.environment()
    if let path = environment["PATH"] {
      #expect(path.split(separator: ":").contains("/usr/bin"))
      #expect(LoginShellPath.loadedEnvironment == environment)
    }
  }
}
