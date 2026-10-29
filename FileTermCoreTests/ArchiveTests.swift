import Foundation
import Testing

@testable import FileTermCore

struct ArchiveTests {
  private func sandbox() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func detectsArchiveNames() {
    for name in ["a.zip", "A.ZIP", "a.tar", "a.tar.gz", "a.tgz", "a.tar.bz2", "a.txz", "a.7z"] {
      #expect(ArchiveFormat.isArchive(name: name), "\(name)")
    }
    for name in ["a.txt", "zip", ".zip", "a.gz", "folder"] {
      #expect(!ArchiveFormat.isArchive(name: name), "\(name)")
    }
    #expect(ArchiveFormat.stem(of: "photos.tar.gz") == "photos")
    #expect(ArchiveFormat.stem(of: "photos.zip") == "photos")
  }

  @Test func uniqueNamesCountUpFinderStyle() throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = ArchiveTool.uniqueURL(in: root, stem: "Archive", ext: "zip")
    #expect(first.lastPathComponent == "Archive.zip")
    try Data().write(to: first)
    #expect(
      ArchiveTool.uniqueURL(in: root, stem: "Archive", ext: "zip").lastPathComponent
        == "Archive 2.zip")
  }

  @Test(arguments: ArchiveFormat.allCases)
  func compressThenExtractRoundTrips(format: ArchiveFormat) async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("docs")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: folder.appendingPathComponent("a.txt"))
    let archive = root.appendingPathComponent("docs." + format.fileExtension)
    try await ArchiveTool.compress(sources: [folder], format: format, destination: archive)
    let out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let created = try await ArchiveTool.extract(archive: archive, into: out)
    #expect(created.map(\.lastPathComponent) == ["docs"])
    #expect(try String(contentsOf: out.appendingPathComponent("docs/a.txt")) == "hello")
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("__MACOSX").path))
  }

  @Test func severalTopLevelItemsGoIntoAFolderNamedAfterTheArchive() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let one = root.appendingPathComponent("one.txt")
    let two = root.appendingPathComponent("two.txt")
    try Data("1".utf8).write(to: one)
    try Data("2".utf8).write(to: two)
    let archive = root.appendingPathComponent("Archive.zip")
    try await ArchiveTool.compress(sources: [one, two], format: .zip, destination: archive)
    let created = try await ArchiveTool.extract(archive: archive, into: root)
    #expect(created.map(\.lastPathComponent) == ["Archive"])
    #expect(
      try String(contentsOf: root.appendingPathComponent("Archive/two.txt")) == "2")
  }

  @Test func singleItemKeepsItsNameUnlessANewFolderIsRequestedAndNeverOverwrites() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("note.txt")
    try Data("keep".utf8).write(to: file)
    let archive = root.appendingPathComponent("note.txt.zip")
    try await ArchiveTool.compress(sources: [file], format: .zip, destination: archive)
    let again = try await ArchiveTool.extract(archive: archive, into: root)
    #expect(again.map(\.lastPathComponent) == ["note 2.txt"])
    #expect(try String(contentsOf: file) == "keep")
    let folder = try await ArchiveTool.extract(archive: archive, into: root, newFolder: true)
    #expect(folder.map(\.lastPathComponent) == ["note.txt 2"])
    #expect(try String(contentsOf: folder[0].appendingPathComponent("note.txt")) == "keep")
  }

  @Test func failedExtractionLeavesNoStagingFolder() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let bad = root.appendingPathComponent("bad.zip")
    try Data("not an archive".utf8).write(to: bad)
    await #expect(throws: (any Error).self) {
      _ = try await ArchiveTool.extract(archive: bad, into: root)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(names == ["bad.zip"])
  }
}
