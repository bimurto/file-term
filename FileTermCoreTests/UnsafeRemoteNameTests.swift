import Foundation
import Testing

@testable import FileTermCore

/// A server chooses the names in its listings, so a name must never climb out of a local folder.
@Suite struct UnsafeRemoteNameTests {
  private actor HostileProvider: FileSystemProvider {
    nonisolated let id = "hostile"
    private let childName: String
    init(childName: String) { self.childName = childName }

    func list(_ location: Location) throws -> [FileEntry] {
      [
        FileEntry(
          location: Location(providerID: id, path: "/tree/evil"), name: childName, kind: .file,
          size: 4),
        FileEntry(
          location: Location(providerID: id, path: "/tree/good.txt"), name: "good.txt", kind: .file,
          size: 4),
      ]
    }
    func stat(_ location: Location) throws -> FileEntry {
      FileEntry(
        location: location,
        name: (location.path as NSString).lastPathComponent,
        kind: location.path == "/tree" ? .directory : .file,
        size: location.path == "/tree" ? nil : 4)
    }
    func read(_ location: Location) throws -> any FileByteReader { Bytes() }
    func write(_ contents: any FileByteReader, to location: Location) throws {
      throw FileSystemError.unsupportedOperation
    }
    func move(_ source: Location, to destination: Location) throws {
      throw FileSystemError.unsupportedOperation
    }
    func delete(_ location: Location) throws { throw FileSystemError.unsupportedOperation }
  }

  private final class Bytes: FileByteReader, @unchecked Sendable {
    private var data: Data? = Data("data".utf8)
    func next() async throws -> Data? {
      defer { data = nil }
      return data
    }
  }

  @Test(arguments: ["", ".", "..", "../evil", "a/b", "/etc/passwd", "a\0b"])
  func rejectsNamesThatAreNotOnePathComponent(name: String) {
    #expect(!FileName.isSafe(name))
  }

  @Test(arguments: ["a.txt", ".hidden", "..hidden", "a..b", "with space", "a\\b", "名前"])
  func acceptsOrdinaryNames(name: String) {
    #expect(FileName.isSafe(name))
  }

  @Test(arguments: ["../escaped.txt", "../../escaped.txt", "..", "sub/../../escaped.txt"])
  func folderCopySkipsAChildWhoseNameLeavesTheDestination(name: String) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("outer/destination")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let top = root.deletingLastPathComponent().deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: top) }

    let local = LocalFileSystemProvider()
    let hostile = HostileProvider(childName: name)
    let transfer = ProviderTransfer(
      registry: ProviderRegistry(providers: [local, hostile]), control: TransferControl())
    let summary = try await transfer.copy(
      sources: [Location(providerID: hostile.id, path: "/tree")],
      to: local.location(for: root))

    let manager = FileManager.default
    #expect(manager.fileExists(atPath: root.appendingPathComponent("tree/good.txt").path))
    #expect(!manager.fileExists(atPath: root.appendingPathComponent("tree/escaped.txt").path))
    #expect(!manager.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
    #expect(!manager.fileExists(atPath: top.appendingPathComponent("outer/escaped.txt").path))
    #expect(summary.skipped == 1)
  }

  @Test func aSourceNamedParentFolderNeverReachesTheConflictPrompt() async throws {
    actor Prompts {
      var count = 0
      func record() { count += 1 }
    }
    let prompts = Prompts()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let local = LocalFileSystemProvider()
    let hostile = HostileProvider(childName: "unused")
    let transfer = ProviderTransfer(
      registry: ProviderRegistry(providers: [local, hostile]), control: TransferControl(),
      resolve: { _ in
        await prompts.record()
        return ConflictResolution(decision: .skip)
      })
    let summary = try await transfer.copy(
      sources: [Location(providerID: hostile.id, path: "/tree/..")],
      to: local.location(for: root))

    #expect(await prompts.count == 0)
    #expect(summary.skipped == 1)
  }

  @Test func ftpListingsDropNamesWithSlashes() {
    let folder = Location(providerID: "ftp", path: "/pub")
    let mlsd = FTPListing.parseMLSD(
      "type=file;size=1; ../../evil\r\ntype=file;size=1; ok.txt\r\n", in: folder, providerID: "ftp")
    #expect(mlsd.map(\.name) == ["ok.txt"])
    let unix = FTPListing.parseList(
      "-rw-r--r-- 1 a b 1 Jan 01 2024 ../../evil\r\n-rw-r--r-- 1 a b 1 Jan 01 2024 ok.txt\r\n",
      in: folder, providerID: "ftp")
    #expect(unix.map(\.name) == ["ok.txt"])
  }
}
