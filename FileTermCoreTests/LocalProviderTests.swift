import Foundation
import Testing

@testable import FileTermCore

struct LocalProviderTests {
  @Test func readsWritesMovesAndDeletesWithoutOverwriting() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let source = provider.location(for: root.appendingPathComponent("source"))
    let target = provider.location(for: root.appendingPathComponent("target"))
    let payload = Data(repeating: 42, count: 150_000)
    try await provider.write(TestByteReader(payload), to: source)
    let info = try await provider.stat(source)
    #expect(info.size == Int64(payload.count))
    let reader = try await provider.read(source)
    var received = Data()
    while let chunk = try await reader.next() { received.append(chunk) }
    #expect(received == payload)
    await #expect(throws: FileSystemError.destinationExists) {
      try await provider.write(TestByteReader(Data()), to: source)
    }
    try await provider.move(source, to: target)
    await #expect(throws: FileSystemError.notFound) { try await provider.stat(source) }
    try await provider.delete(target)
    await #expect(throws: FileSystemError.notFound) { try await provider.stat(target) }
  }

  @Test func recognizesSymlinksAndRejectsForeignLocations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(
      atPath: link.path, withDestinationPath: "/does-not-exist")
    let provider = LocalFileSystemProvider()
    let entry = try await provider.stat(provider.location(for: link))
    #expect(entry.kind == .symbolicLink)
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await provider.list(Location(providerID: "remote", path: "/"))
    }
  }

  @Test func normalizesPermissionFailures() {
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
    #expect(LocalFileSystemProvider.normalized(error) as? FileSystemError == .permissionDenied)
  }

  @Test func listsMetadataAndOmitsHiddenFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("hello".utf8).write(to: root.appendingPathComponent("café.txt"))
    try Data().write(to: root.appendingPathComponent(".hidden"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Folder"), withIntermediateDirectories: false)
    let provider = LocalFileSystemProvider()
    let entries = try await provider.list(provider.location(for: root))
    #expect(entries.map(\.name).sorted() == ["Folder", "café.txt"])
    let file = try #require(entries.first { $0.name == "café.txt" })
    #expect(file.kind == .file)
    #expect(file.size == 5)
    #expect(file.createdAt != nil)
    #expect(file.modifiedAt != nil)
  }
}

actor TestByteReader: FileByteReader {
  var data: Data?
  init(_ data: Data) { self.data = data }
  func next() -> Data? {
    defer { data = nil }
    return data
  }
}
