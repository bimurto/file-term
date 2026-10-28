import Foundation
import Testing

@testable import FileTermCore

struct SSHCommandTests {
  private let knownHosts = URL(
    fileURLWithPath: "/Users/me/Library/Application Support/FileTerm/known_hosts")

  @Test func sftpArgumentsAreStrictAndNonInteractiveWithoutASecret() {
    let target = SSHTarget(host: "example.com", port: 2222, username: "tester")
    let arguments = SSHCommand.sftpArguments(
      target: target, knownHosts: knownHosts, hasSecret: false)
    #expect(arguments.suffix(3) == ["--", "example.com", "sftp"])
    #expect(arguments.starts(with: ["-T", "-s"]))
    #expect(arguments.contains("BatchMode=yes"))
    #expect(arguments.contains("StrictHostKeyChecking=yes"))
    #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-p" && $1 == "2222" })
    #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-l" && $1 == "tester" })
    #expect(
      arguments.contains(
        "UserKnownHostsFile=\"/Users/me/Library/Application Support/FileTerm/known_hosts\" ~/.ssh/known_hosts"
      ))
    let withSecret = SSHCommand.sftpArguments(
      target: target, knownHosts: knownHosts, hasSecret: true)
    #expect(!withSecret.contains("BatchMode=yes"))
  }

  @Test func keyFileLimitsIdentitiesAndExpandsTilde() {
    let target = SSHTarget(host: "h", privateKeyPath: " ~/.ssh/work_key ")
    let expected = NSString(string: "~/.ssh/work_key").expandingTildeInPath
    #expect(target.privateKeyPath == expected)
    let arguments = SSHCommand.sftpArguments(
      target: target, knownHosts: knownHosts, hasSecret: false)
    #expect(zip(arguments, arguments.dropFirst()).contains { $0 == "-i" && $1 == expected })
    #expect(arguments.contains("IdentitiesOnly=yes"))
    #expect(SSHTarget(host: "h", privateKeyPath: "  ").privateKeyPath == nil)
  }

  @Test func hostComesAfterTheOptionTerminator() {
    let target = SSHTarget(host: "-oProxyCommand=x")
    let arguments = SSHCommand.terminalArguments(
      target: target, knownHosts: knownHosts, directory: nil)
    let marker = arguments.firstIndex(of: "--")
    #expect(marker != nil && arguments[marker! + 1] == "-oProxyCommand=x")
  }

  @Test func ipv6HostsLoseTheirBrackets() {
    #expect(SSHTarget(host: "[::1]").host == "::1")
  }

  @Test func terminalCommandQuotesTheRemoteDirectory() {
    let target = SSHTarget(host: "h", username: "me")
    let arguments = SSHCommand.terminalArguments(
      target: target, knownHosts: knownHosts, directory: "/srv/it's here")
    #expect(arguments.first == "-t")
    #expect(arguments.last == "cd '/srv/it'\\''s here' && exec \"$SHELL\" -l")
  }

  @Test func terminalCommandIgnoresRelativeDirectories() {
    let arguments = SSHCommand.terminalArguments(
      target: SSHTarget(host: "h"), knownHosts: knownHosts, directory: "relative")
    #expect(arguments.last == "h")
  }

  @Test func askpassKeepsTheSecretPrivateAndRemovesIt() throws {
    let askpass = try SSHAskpass(secret: "pa ss'word")
    let script = try #require(askpass.environment["SSH_ASKPASS"])
    #expect(askpass.environment["SSH_ASKPASS_REQUIRE"] == "force")
    let folder = URL(fileURLWithPath: script).deletingLastPathComponent()
    let permissions = { (url: URL) in
      try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }
    #expect(try permissions(folder) == 0o700)
    #expect(try permissions(folder.appendingPathComponent("secret")) == 0o600)

    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: script)
    process.standardOutput = output
    try process.run()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(text == "pa ss'word\n")

    askpass.remove()
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(throws: FileSystemError.self) { try SSHAskpass(secret: "a\nb") }
  }
}

struct HostKeyStoreTests {
  private let key = HostKey(
    type: "ssh-ed25519",
    blob: "AAAAC3NzaC1lZDI1NTE5AAAAILsDCh5m+CJP4O3x9/4wGhLcOnVU20Z5j+X9TfkV86rU")

  private func store() -> HostKeyStore {
    HostKeyStore(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("fileterm-\(UUID().uuidString)/known_hosts"))
  }

  @Test func fingerprintMatchesSSHKeygen() {
    #expect(key.fingerprint == "SHA256:DhJYvQCPgSQA9Y9JN8bbYNLl1pRhfc74ceXtpnZXxyo")
    #expect(HostKey(type: "x", blob: "***").fingerprint == nil)
  }

  @Test func patternsNamePortsLikeKnownHosts() {
    #expect(HostKeyStore.hostPattern(host: "a.example", port: nil) == "a.example")
    #expect(HostKeyStore.hostPattern(host: "a.example", port: 22) == "a.example")
    #expect(HostKeyStore.hostPattern(host: "127.0.0.1", port: 2222) == "[127.0.0.1]:2222")
  }

  @Test func parsesKeyscanOutputAndSkipsComments() {
    let output = """
      # 127.0.0.1:2222 SSH-2.0-OpenSSH_9.9
      [127.0.0.1]:2222 ssh-ed25519 \(key.blob)
      # 127.0.0.1:2222 SSH-2.0-OpenSSH_9.9
      [127.0.0.1]:2222 ssh-ed25519 \(key.blob)
      [127.0.0.1]:2222 ssh-rsa AAAAB3Nza
      garbage
      """
    #expect(
      HostKeyStore.parseScan(output) == [key, HostKey(type: "ssh-rsa", blob: "AAAAB3Nza")])
  }

  @Test func trustWritesOnceWithPrivatePermissions() throws {
    let store = store()
    defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
    let target = SSHTarget(host: "127.0.0.1", port: 2222)
    try store.trust([key], for: target)
    try store.trust([key], for: target)
    let text = try String(contentsOf: store.fileURL, encoding: .utf8)
    #expect(text == "[127.0.0.1]:2222 ssh-ed25519 \(key.blob)\n")
    let permissions =
      try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[
        .posixPermissions] as? Int
    #expect(permissions == 0o600)
    try store.trust([key], for: SSHTarget(host: "other.example"))
    #expect(
      try String(contentsOf: store.fileURL, encoding: .utf8).split(separator: "\n").count == 2)
  }
}
