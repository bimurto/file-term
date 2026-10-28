import Foundation
import Testing

@testable import FileTermCore

/// Runs against the servers in dev/docker-compose.yml. Skipped unless FILETERM_LIVE=1.
@Suite(
  .enabled(if: ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1"), .serialized)
struct LiveServerTests {
  private let user = "tester"
  private let secret = "testpass123"

  private func providers() -> (dav1: WebDAVProvider, dav2: WebDAVProvider, s3: S3Provider) {
    (
      WebDAVProvider(
        id: "dav1", baseURL: URL(string: "http://127.0.0.1:8080")!, username: user, password: secret
      ),
      WebDAVProvider(
        id: "dav2", baseURL: URL(string: "http://127.0.0.1:8081")!, username: user, password: secret
      ),
      S3Provider(
        id: "s3", endpoint: URL(string: "http://127.0.0.1:9000")!, region: "us-east-1",
        accessKey: user, secretKey: secret)
    )
  }

  private func put(_ text: String, _ location: Location, in provider: any FileSystemProvider)
    async throws
  {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try text.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    try await provider.write(
      try await LocalFileSystemProvider().read(Location(providerID: "local", path: file.path)),
      to: location)
  }

  private func text(_ location: Location, in provider: any FileSystemProvider) async throws
    -> String
  {
    let reader = try await provider.read(location)
    var data = Data()
    while let chunk = try await reader.next() { data.append(chunk) }
    return String(decoding: data, as: UTF8.self)
  }

  /// New folder, rename, rename onto an existing name, download and delete on one provider.
  private func exercise(
    _ provider: any FileSystemProvider, root: String, registry: ProviderRegistry
  )
    async throws
  {
    let base = Location(providerID: provider.id, path: root)
    let folder = try await ProviderItemOperations.createFolder(in: base, registry: registry)
    #expect(folder.path.hasSuffix("/untitled folder"))
    let again = try await ProviderItemOperations.createFolder(in: base, registry: registry)
    #expect(again.path.hasSuffix("/untitled folder 2"))

    let renamed = try await ProviderItemOperations.rename(folder, to: "docs", registry: registry)
    let file = ProviderTransfer.child(renamed, "a b.txt")
    try await put("hello", file, in: provider)
    let other = ProviderTransfer.child(renamed, "c.txt")
    try await put("other", other, in: provider)

    let moved = try await ProviderItemOperations.rename(file, to: "renamed.txt", registry: registry)
    #expect(try await text(moved, in: provider) == "hello")
    await #expect(throws: FileSystemError.destinationExists) {
      try await ProviderItemOperations.rename(moved, to: "c.txt", registry: registry)
    }
    #expect(try await text(other, in: provider) == "other")

    try await provider.delete(renamed)
    await #expect(throws: FileSystemError.notFound) { _ = try await provider.stat(renamed) }
    try await provider.delete(again)
  }

  @Test func webDAVEdits() async throws {
    let p = providers()
    let registry = ProviderRegistry(providers: [p.dav1])
    let root = Location(providerID: "dav1", path: "/t3b-\(UUID().uuidString.prefix(8))")
    try await p.dav1.createDirectory(root)
    do {
      try await exercise(p.dav1, root: root.path, registry: registry)
    } catch {
      try? await p.dav1.delete(root)
      throw error
    }
    try await p.dav1.delete(root)
  }

  @Test func s3Edits() async throws {
    let p = providers()
    let registry = ProviderRegistry(providers: [p.s3])
    let root = Location(providerID: "s3", path: "/test/t3b-\(UUID().uuidString.prefix(8))")
    try await p.s3.createDirectory(root)
    do {
      try await exercise(p.s3, root: root.path, registry: registry)
      // An empty folder renames; one with items is refused.
      let folder = try await ProviderItemOperations.createFolder(in: root, registry: registry)
      let empty = try await ProviderItemOperations.rename(folder, to: "empty", registry: registry)
      try await put("x", ProviderTransfer.child(empty, "f.txt"), in: p.s3)
      await #expect(throws: (any Error).self) {
        try await ProviderItemOperations.rename(empty, to: "full", registry: registry)
      }
    } catch {
      try? await p.s3.delete(root)
      throw error
    }
    try await p.s3.delete(root)
  }

  @Test func moveBetweenServersAndFromLocal() async throws {
    let p = providers()
    let local = LocalFileSystemProvider()
    let registry = ProviderRegistry(providers: [local, p.dav1, p.dav2, p.s3])
    let tag = UUID().uuidString.prefix(8)
    let source = Location(providerID: "dav1", path: "/t3b-src-\(tag)")
    let target = Location(providerID: "dav2", path: "/t3b-dst-\(tag)")
    let bucket = Location(providerID: "s3", path: "/test/t3b-\(tag)")
    try await p.dav1.createDirectory(source)
    try await p.dav2.createDirectory(target)
    try await p.s3.createDirectory(bucket)
    defer {
      Task {
        try? await p.dav1.delete(source)
        try? await p.dav2.delete(target)
        try? await p.s3.delete(bucket)
      }
    }
    let tree = ProviderTransfer.child(source, "tree")
    try await p.dav1.createDirectory(tree)
    try await put("one", ProviderTransfer.child(tree, "1.txt"), in: p.dav1)
    try await put("two", ProviderTransfer.child(source, "2 x.txt"), in: p.dav1)

    // WebDAV to WebDAV: sources vanish after a clean move.
    let engine = ProviderTransfer(registry: registry, control: TransferControl())
    let summary = try await engine.move(
      sources: [tree, ProviderTransfer.child(source, "2 x.txt")], to: target)
    #expect(summary.failed == 0 && summary.skipped == 0)
    #expect(try await text(ProviderTransfer.child(target, "tree/1.txt"), in: p.dav2) == "one")
    #expect(try await text(ProviderTransfer.child(target, "2 x.txt"), in: p.dav2) == "two")
    #expect(try await p.dav1.list(source).isEmpty)

    // WebDAV to S3, then a skipped conflict keeps the source.
    _ = try await ProviderTransfer(registry: registry, control: TransferControl())
      .move(sources: [ProviderTransfer.child(target, "tree")], to: bucket)
    #expect(try await text(ProviderTransfer.child(bucket, "tree/1.txt"), in: p.s3) == "one")
    await #expect(throws: FileSystemError.notFound) {
      _ = try await p.dav2.stat(ProviderTransfer.child(target, "tree"))
    }
    // Moving into the folder an item is already in is refused and loses nothing.
    await #expect(throws: FileSystemError.io("The items are already in this folder.")) {
      _ = try await ProviderTransfer(registry: registry, control: TransferControl())
        .move(sources: [ProviderTransfer.child(target, "2 x.txt")], to: target)
    }
    #expect(try await text(ProviderTransfer.child(target, "2 x.txt"), in: p.dav2) == "two")
  }
}

/// FTP and FTP-TLS against the `ftp` service (port 2121). Skipped unless FILETERM_LIVE=1.
@Suite(
  .enabled(if: ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1"), .serialized)
struct LiveFTPTests {
  private func provider(
    secure: Bool = false, insecure: Bool = false, active: Bool = false,
    password: String = "testpass123",
    port: Int = 2121
  ) -> FTPProvider {
    FTPProvider(
      id: "ftp", host: "127.0.0.1", port: port, username: "tester", password: password,
      secure: secure, activeMode: active, allowInvalidCertificate: insecure)
  }

  private func put(_ text: String, _ location: Location, in provider: FTPProvider) async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try text.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let reader = try await LocalFileSystemProvider().read(
      Location(providerID: "local", path: file.path))
    try await provider.write(reader, to: location)
  }

  private func text(_ location: Location, in provider: FTPProvider) async throws -> String {
    let reader = try await provider.read(location)
    var data = Data()
    while let chunk = try await reader.next() { data.append(chunk) }
    return String(decoding: data, as: UTF8.self)
  }

  private func exercise(_ ftp: FTPProvider) async throws {
    let root = Location(providerID: "ftp", path: "/t5-\(UUID().uuidString.prefix(8))")
    try await ftp.validate(root: "/")
    try await ftp.createDirectory(root)
    do {
      await #expect(throws: FileSystemError.destinationExists) {
        try await ftp.createDirectory(root)
      }
      let file = ProviderTransfer.child(root, "a b é.txt")
      try await put("hello ftp", file, in: ftp)
      #expect(try await text(file, in: ftp) == "hello ftp")
      await #expect(throws: FileSystemError.destinationExists) {
        try await put("again", file, in: ftp)
      }
      let entry = try await ftp.stat(file)
      #expect(entry.kind == .file && entry.size == 9)

      let sub = ProviderTransfer.child(root, "sub")
      try await ftp.createDirectory(sub)
      let renamed = ProviderTransfer.child(sub, "renamed.txt")
      try await ftp.move(file, to: renamed)
      #expect(try await text(renamed, in: ftp) == "hello ftp")
      await #expect(throws: FileSystemError.notFound) { _ = try await ftp.stat(file) }
      #expect(try await ftp.list(root).map(\.name) == ["sub"])
    } catch {
      try? await ftp.delete(root)
      throw error
    }
    try await ftp.delete(root)
    await #expect(throws: FileSystemError.notFound) { _ = try await ftp.stat(root) }
  }

  @Test func plainFTPEdits() async throws { try await exercise(provider()) }

  @Test func explicitTLSNeedsTheInvalidCertificateOption() async throws {
    await #expect(throws: FTPError.certificate) {
      try await provider(secure: true).validate(root: "/")
    }
    // The test server takes about two seconds to log in, so TLS gets a shorter round trip.
    let tls = provider(secure: true, insecure: true)
    let file = Location(providerID: "ftp", path: "/t5-tls-\(UUID().uuidString.prefix(8)).txt")
    try await put("secret", file, in: tls)
    let downloaded = try await text(file, in: tls)
    try await tls.delete(file)
    #expect(downloaded == "secret")
  }

  @Test func wrongPasswordAndClosedPortHaveClearMessages() async throws {
    await #expect(throws: FTPError.loginDenied) {
      try await provider(password: "wrong").validate(root: "/")
    }
    await #expect(throws: FTPError.cannotConnect(host: "127.0.0.1", port: 2999)) {
      try await provider(port: 2999).validate(root: "/")
    }
  }

  @Test func activeModeReportsWhyItFailedInsideDocker() async throws {
    await #expect(throws: FTPError.activeModeFailed) {
      try await provider(active: true).validate(root: "/")
    }
  }

  @Test func downloadsAndUploadsAMultiChunkFile() async throws {
    let ftp = provider()
    let location = Location(providerID: "ftp", path: "/t5-big-\(UUID().uuidString.prefix(8)).bin")
    let big = String(repeating: "0123456789abcdef", count: 40_000)  // 640 KB
    try await put(big, location, in: ftp)
    let downloaded = try await text(location, in: ftp)
    try await ftp.delete(location)
    #expect(downloaded == big)
  }
}

/// SFTP against the `sftp` service (port 2222, chrooted: the user works in /upload). Skipped
/// unless FILETERM_LIVE=1. Key authentication needs an authorized key mounted into the container
/// and is covered by the argument tests instead.
@Suite(
  .enabled(if: ProcessInfo.processInfo.environment["FILETERM_LIVE"] == "1"), .serialized)
struct LiveSFTPTests {
  private let target = SSHTarget(host: "127.0.0.1", port: 2222, username: "tester")

  private func knownHosts() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-live-\(UUID().uuidString)/known_hosts")
  }

  private func provider(knownHosts: URL, password: String = "testpass123") -> SFTPProvider {
    SFTPProvider(id: "sftp", target: target, password: password, knownHosts: knownHosts)
  }

  private func trusted() async throws -> (SFTPProvider, URL) {
    let file = knownHosts()
    let store = HostKeyStore(fileURL: file)
    try store.trust(try await store.scan(target), for: target)
    return (provider(knownHosts: file), file)
  }

  private func put(_ text: String, _ location: Location, in provider: SFTPProvider) async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try text.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    try await provider.write(
      try await LocalFileSystemProvider().read(Location(providerID: "local", path: file.path)),
      to: location)
  }

  private func text(_ location: Location, in provider: SFTPProvider) async throws -> String {
    let reader = try await provider.read(location)
    var data = Data()
    while let chunk = try await reader.next() { data.append(chunk) }
    return String(decoding: data, as: UTF8.self)
  }

  @Test func anUnknownServerIsRefusedUntilItsKeyIsTrusted() async throws {
    let file = knownHosts()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    await #expect(throws: SFTPError.unknownHostKey(host: "127.0.0.1", port: 2222)) {
      _ = try await self.provider(knownHosts: file).resolveRoot("upload")
    }
    #expect(!FileManager.default.fileExists(atPath: file.path))

    let store = HostKeyStore(fileURL: file)
    let keys = try await store.scan(target)
    #expect(!keys.isEmpty && keys.allSatisfy { $0.fingerprint?.hasPrefix("SHA256:") == true })
    try store.trust(keys, for: target)
    let sftp = provider(knownHosts: file)
    #expect(try await sftp.resolveRoot("upload") == "/upload")
    try await sftp.validate(root: "/upload")
  }

  @Test func aWrongPasswordIsReported() async throws {
    let (_, file) = try await trusted()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    await #expect(throws: SFTPError.loginDenied) {
      try await self.provider(knownHosts: file, password: "wrong").validate(root: "/upload")
    }
  }

  @Test func editsOnTheServer() async throws {
    let (sftp, file) = try await trusted()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let root = Location(providerID: "sftp", path: "/upload/t6-\(UUID().uuidString.prefix(8))")
    try await sftp.createDirectory(root)
    do {
      await #expect(throws: FileSystemError.destinationExists) {
        try await sftp.createDirectory(root)
      }
      let item = ProviderTransfer.child(root, "a b é.txt")
      try await put("hello sftp", item, in: sftp)
      #expect(try await text(item, in: sftp) == "hello sftp")
      await #expect(throws: FileSystemError.destinationExists) {
        try await self.put("again", item, in: sftp)
      }
      let entry = try await sftp.stat(item)
      #expect(entry.kind == .file && entry.size == 10)

      let sub = ProviderTransfer.child(root, "sub")
      try await sftp.createDirectory(sub)
      let renamed = ProviderTransfer.child(sub, "renamed.txt")
      try await sftp.move(item, to: renamed)
      #expect(try await text(renamed, in: sftp) == "hello sftp")
      await #expect(throws: FileSystemError.notFound) { _ = try await sftp.stat(item) }
      #expect(try await sftp.list(root).map(\.name) == ["sub"])
    } catch {
      try? await sftp.delete(root)
      throw error
    }
    try await sftp.delete(root)
    await #expect(throws: FileSystemError.notFound) { _ = try await sftp.stat(root) }
  }
}
