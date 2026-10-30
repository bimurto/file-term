import Foundation
import Testing

@testable import FileTermCore

/// M14.10: connect, list, upload, download, rename and delete, once per protocol, against the
/// servers in dev/docker-compose.yml. Skipped unless FILETERM_LIVE=1.
@Suite(
  .enabled(if: ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1"), .serialized)
struct RemoteSmokeTests {
  private static let user = "tester"
  private static let secret = "testpass123"

  private func smoke(_ provider: any FileSystemProvider, in parent: String) async throws {
    let registry = ProviderRegistry(providers: [provider])
    let base = Location(providerID: provider.id, path: parent)
    // Connect and list.
    _ = try await provider.list(base)

    let root = ProviderTransfer.child(base, "m14-\(UUID().uuidString.prefix(8))")
    try await provider.createDirectory(root)
    do {
      // Upload.
      let contents = "smoke test \(UUID().uuidString)"
      let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try contents.write(to: local, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: local) }
      let file = ProviderTransfer.child(root, "upload.txt")
      try await provider.write(
        try await LocalFileSystemProvider().read(Location(providerID: "local", path: local.path)),
        to: file)
      #expect(try await provider.list(root).map(\.name) == ["upload.txt"])

      // Download.
      #expect(try await download(file, from: provider) == contents)

      // Rename.
      let renamed = try await ProviderItemOperations.rename(
        file, to: "renamed.txt", registry: registry)
      #expect(try await provider.list(root).map(\.name) == ["renamed.txt"])
      #expect(try await download(renamed, from: provider) == contents)

      // Delete.
      try await provider.delete(renamed)
      #expect(try await provider.list(root).isEmpty)
    } catch {
      try? await provider.delete(root)
      throw error
    }
    try await provider.delete(root)
    #expect(try await !provider.list(base).map(\.location).contains(root))
  }

  private func download(_ location: Location, from provider: any FileSystemProvider) async throws
    -> String
  {
    let reader = try await provider.read(location)
    var data = Data()
    while let chunk = try await reader.next() { data.append(chunk) }
    return String(decoding: data, as: UTF8.self)
  }

  private func ftp(secure: Bool) -> FTPProvider {
    FTPProvider(
      id: "ftp", host: "127.0.0.1", port: 2121, username: Self.user, password: Self.secret,
      secure: secure, activeMode: false, allowInvalidCertificate: secure, textEncoding: "UTF-8")
  }

  private func s3(id: String) -> S3Provider {
    S3Provider(
      id: id, endpoint: URL(string: "http://127.0.0.1:9000")!, region: "us-east-1",
      accessKey: Self.user, secretKey: Self.secret)
  }

  @Test func sftp() async throws {
    let target = SSHTarget(host: "127.0.0.1", port: 2222, username: Self.user)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-smoke-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let hosts = folder.appendingPathComponent("known_hosts")
    let store = HostKeyStore(fileURL: hosts)
    try store.trust(try await store.scan(target), for: target)
    let provider = SFTPProvider(
      id: "sftp", target: target, password: Self.secret, textEncoding: "UTF-8", knownHosts: hosts)
    try await smoke(provider, in: "/upload")
  }

  @Test func plainFTP() async throws { try await smoke(ftp(secure: false), in: "/") }

  @Test func ftpTLS() async throws { try await smoke(ftp(secure: true), in: "/") }

  @Test func webDAV() async throws {
    let provider = WebDAVProvider(
      id: "dav", baseURL: URL(string: "http://127.0.0.1:8080")!, username: Self.user,
      password: Self.secret)
    try await smoke(provider, in: "/")
  }

  @Test func amazonS3() async throws { try await smoke(s3(id: "s3"), in: "/test") }

  /// Uses the S3 stand-in, so this covers FileTerm's B2 path but not Backblaze's own service.
  @Test func backblazeB2() async throws { try await smoke(s3(id: "b2"), in: "/test2") }
}
