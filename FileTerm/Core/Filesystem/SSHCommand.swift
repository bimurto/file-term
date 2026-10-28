import Foundation

/// Where an ssh connection goes and how it signs in. Brackets around an IPv6 address are dropped
/// because ssh takes the bare address.
public struct SSHTarget: Equatable, Sendable {
  public let host: String
  public let port: Int?
  public let username: String?
  public let privateKeyPath: String?

  public init(
    host: String, port: Int? = nil, username: String? = nil, privateKeyPath: String? = nil
  ) {
    self.host =
      host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    self.port = port
    self.username = username.flatMap { $0.isEmpty ? nil : $0 }
    let key = privateKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.privateKeyPath = key.isEmpty ? nil : (key as NSString).expandingTildeInPath
  }

  public init(profile: ConnectionProfile) throws {
    let endpoint = try profile.sshEndpoint()
    self.init(
      host: endpoint.host, port: endpoint.port, username: profile.username,
      privateKeyPath: profile.privateKeyPath)
  }
}

/// Builds `ssh` command lines. Host keys are always checked strictly: a key is trusted only when
/// it is in the app's own known_hosts file or the user's `~/.ssh/known_hosts`.
public enum SSHCommand {
  public static let executable = URL(fileURLWithPath: "/usr/bin/ssh")

  /// ssh runs with no terminal and speaks SFTP on its standard input and output.
  public static func sftpArguments(target: SSHTarget, knownHosts: URL, hasSecret: Bool) -> [String]
  {
    var arguments = [
      "-T", "-s",
      "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15",
      "-o", "ClearAllForwardings=yes", "-o", "LogLevel=ERROR",
      "-o", "NumberOfPasswordPrompts=1",
    ]
    // Without a password there is nobody to answer a prompt, so ssh must not wait for one.
    if !hasSecret { arguments += ["-o", "BatchMode=yes"] }
    arguments += identityArguments(target: target) + trustArguments(knownHosts: knownHosts)
    return arguments + ["--", target.host, "sftp"]
  }

  /// Arguments for an interactive session started in a terminal. ssh asks for any password
  /// itself; the app never types it. A `directory` starts the remote shell there.
  public static func terminalArguments(
    target: SSHTarget, knownHosts: URL, directory: String?
  ) -> [String] {
    var arguments =
      ["-t"] + identityArguments(target: target) + trustArguments(knownHosts: knownHosts)
    arguments += ["--", target.host]
    if let directory, directory.hasPrefix("/") {
      arguments.append("cd \(remoteQuote(directory)) && exec \"$SHELL\" -l")
    }
    return arguments
  }

  private static func identityArguments(target: SSHTarget) -> [String] {
    var arguments: [String] = []
    if let port = target.port { arguments += ["-p", String(port)] }
    if let username = target.username { arguments += ["-l", username] }
    if let key = target.privateKeyPath { arguments += ["-i", key, "-o", "IdentitiesOnly=yes"] }
    return arguments
  }

  private static func trustArguments(knownHosts: URL) -> [String] {
    [
      "-o", "StrictHostKeyChecking=yes",
      "-o", "UserKnownHostsFile=\"\(knownHosts.path)\" ~/.ssh/known_hosts",
    ]
  }

  /// POSIX single quotes for the remote shell.
  static func remoteQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

/// A one-shot `SSH_ASKPASS` helper so ssh can read a password or key passphrase without a
/// terminal. The secret lives in a 0600 file inside a 0700 folder and is deleted by `remove()`,
/// which must be called once ssh has signed in or exited.
public final class SSHAskpass: @unchecked Sendable {
  private let directory: URL

  public init(secret: String) throws {
    guard !secret.contains("\n"), !secret.contains("\r") else {
      throw FileSystemError.io("Passwords cannot contain line breaks.")
    }
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fileterm-ssh-\(UUID().uuidString)")
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let secretFile = directory.appendingPathComponent("secret")
    let script = directory.appendingPathComponent("askpass")
    guard
      manager.createFile(
        atPath: secretFile.path, contents: Data((secret + "\n").utf8),
        attributes: [.posixPermissions: 0o600]),
      manager.createFile(
        atPath: script.path,
        contents: Data("#!/bin/sh\nexec /bin/cat \"$(dirname \"$0\")/secret\"\n".utf8),
        attributes: [.posixPermissions: 0o700])
    else {
      try? manager.removeItem(at: directory)
      throw FileSystemError.io("Could not prepare the SSH login.")
    }
  }

  deinit { remove() }

  public var environment: [String: String] {
    [
      "SSH_ASKPASS": directory.appendingPathComponent("askpass").path,
      "SSH_ASKPASS_REQUIRE": "force",
    ]
  }

  public func remove() { try? FileManager.default.removeItem(at: directory) }
}
