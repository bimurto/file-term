import CryptoKit
import Foundation

public struct HostKey: Equatable, Sendable {
  /// The key type as ssh names it, for example `ssh-ed25519`.
  public let type: String
  /// The base64 public key blob.
  public let blob: String

  public init(type: String, blob: String) {
    self.type = type
    self.blob = blob
  }

  /// The algorithm in the words people use: ED25519, RSA, ECDSA.
  public var algorithm: String {
    type.hasPrefix("ecdsa") ? "ECDSA" : type.replacingOccurrences(of: "ssh-", with: "").uppercased()
  }

  /// `SHA256:…`, the form `ssh-keygen -l` prints and ssh shows when it asks about a new host.
  public var fingerprint: String? {
    guard let data = Data(base64Encoded: blob) else { return nil }
    let digest = Data(SHA256.hash(data: data)).base64EncodedString()
    return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
  }
}

/// The app's own known_hosts file, written only after the user accepts a key. ssh also reads
/// `~/.ssh/known_hosts`, which this type never changes.
public struct HostKeyStore: Sendable {
  public let fileURL: URL
  private let keyscan: URL

  public init(
    fileURL: URL = HostKeyStore.defaultFileURL,
    keyscan: URL = URL(fileURLWithPath: "/usr/bin/ssh-keyscan")
  ) {
    self.fileURL = fileURL
    self.keyscan = keyscan
  }

  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("FileTerm/known_hosts")
  }

  /// How known_hosts names a server: the host alone on port 22, else `[host]:port`.
  public static func hostPattern(host: String, port: Int?) -> String {
    guard let port, port != 22 else { return host }
    return "[\(host)]:\(port)"
  }

  /// Asks the server for its public keys without signing in.
  public func scan(_ target: SSHTarget) async throws -> [HostKey] {
    guard FileManager.default.isExecutableFile(atPath: keyscan.path) else {
      throw FileSystemError.io("ssh-keyscan was not found on this Mac.")
    }
    var arguments = ["-T", "10"]
    if let port = target.port { arguments += ["-p", String(port)] }
    arguments += ["--", target.host]
    let output = try await Self.run(keyscan, arguments)
    let keys = Self.parseScan(output)
    guard !keys.isEmpty else {
      throw FileSystemError.io("The server did not present a host key.")
    }
    return keys
  }

  /// Adds the keys for a server the user accepted. Keys already present are not repeated.
  public func trust(_ keys: [HostKey], for target: SSHTarget) throws {
    let pattern = Self.hostPattern(host: target.host, port: target.port)
    let manager = FileManager.default
    try manager.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    var added = false
    for key in keys {
      let line = "\(pattern) \(key.type) \(key.blob)"
      if existing.split(separator: "\n").contains(where: { $0 == line }) { continue }
      if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
      existing += line + "\n"
      added = true
    }
    guard added else { return }
    guard
      manager.createFile(
        atPath: fileURL.path, contents: Data(existing.utf8), attributes: [.posixPermissions: 0o600])
    else { throw FileSystemError.io("Could not save the host key.") }
  }

  /// Reads `ssh-keyscan` output: `host type blob` lines and `#` comments.
  static func parseScan(_ output: String) -> [HostKey] {
    var keys: [HostKey] = []
    for line in output.split(separator: "\n") where !line.hasPrefix("#") {
      let fields = line.split(separator: " ")
      guard fields.count >= 3 else { continue }
      let key = HostKey(type: String(fields[1]), blob: String(fields[2]))
      if !keys.contains(key) { keys.append(key) }
    }
    return keys
  }

  private static func run(_ executable: URL, _ arguments: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global().async {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
          try process.run()
          let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
          process.waitUntilExit()
          continuation.resume(returning: String(decoding: data, as: UTF8.self))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
