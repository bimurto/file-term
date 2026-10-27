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
