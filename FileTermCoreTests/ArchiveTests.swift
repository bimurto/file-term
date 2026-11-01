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

  /// bsdtar reads these as options, directory changes or archive includes unless they are guarded.
  @Test(arguments: ["--version", "-v", "-Cother", "@included.txt"], [ArchiveFormat.tar, .zip])
  func compressKeepsNamesThatLookLikeOptions(name: String, format: ArchiveFormat) async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let tricky = root.appendingPathComponent(name)
    let plain = root.appendingPathComponent("plain.txt")
    try Data("tricky".utf8).write(to: tricky)
    try Data("plain".utf8).write(to: plain)
    let archive = root.appendingPathComponent("Archive." + format.fileExtension)
    try await ArchiveTool.compress(sources: [tricky, plain], format: format, destination: archive)
    let out = root.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    _ = try await ArchiveTool.extract(archive: archive, into: out)
    #expect(try String(contentsOf: out.appendingPathComponent("Archive/\(name)")) == "tricky")
    #expect(try String(contentsOf: out.appendingPathComponent("Archive/plain.txt")) == "plain")
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

  @Test func emptyArchiveReportsThatItHasNothingToExtract() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let empty = root.appendingPathComponent("empty.zip")
    try Data().write(to: empty)
    await #expect(throws: ArchiveToolError.empty("empty.zip")) {
      _ = try await ArchiveTool.extract(archive: empty, into: root)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["empty.zip"])
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

struct ArchiveProviderTests {
  private func makeArchive() async throws -> (root: URL, archive: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let tree = root.appendingPathComponent("pkg")
    try FileManager.default.createDirectory(
      at: tree.appendingPathComponent("sub dir/deep"), withIntermediateDirectories: true)
    try Data("top".utf8).write(to: tree.appendingPathComponent("readme.txt"))
    try Data("needle inside".utf8).write(to: tree.appendingPathComponent("sub dir/deep/é[1].txt"))
    try Data("hidden".utf8).write(to: tree.appendingPathComponent(".secret"))
    let archive = root.appendingPathComponent("pkg.zip")
    try await ArchiveTool.compress(sources: [tree], format: .zip, destination: archive)
    return (root, archive)
  }

  @Test func listsNestedFoldersAndHidesHiddenItemsOnRequest() async throws {
    let (root, archive) = try await makeArchive()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let top = try await provider.list(Location(providerID: provider.id, path: "/"))
    #expect(top.map(\.name) == ["pkg"])
    #expect(top[0].kind == .directory)
    let pkg = Location(providerID: provider.id, path: "/pkg")
    let visible = try await provider.list(pkg, includeHidden: false)
    #expect(visible.map(\.name) == ["readme.txt", "sub dir"])
    #expect(try await provider.list(pkg).map(\.name).contains(".secret"))
    let readme = try await provider.stat(Location(providerID: provider.id, path: "/pkg/readme.txt"))
    #expect(readme.size == 3)
    #expect(readme.modifiedAt != nil)
  }

  @Test func readsAMemberWithSpecialCharactersInItsName() async throws {
    let (root, archive) = try await makeArchive()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let location = Location(providerID: provider.id, path: "/pkg/sub dir/deep/é[1].txt")
    let reader = try await provider.read(location)
    var data = Data()
    while let chunk = try await reader.next() { data.append(chunk) }
    #expect(String(decoding: data, as: UTF8.self) == "needle inside")
  }

  /// `-C` is a directory change even after `--` when creating, so that member is stored as `./-C…`.
  @Test(arguments: [("--version", "--version"), ("-v", "-v"), ("-Cother", "./-Cother")])
  func readsAMemberNamedLikeAnOption(name: String, stored: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("member".utf8).write(to: root.appendingPathComponent(name))
    let archive = root.appendingPathComponent("a.tar")
    try await ProcessRunner.run(
      "/bin/sh",
      ["-c", "cd \"$1\" && /usr/bin/bsdtar -cf a.tar -- \"$2\"", "sh", root.path, stored])
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let reader = try await provider.read(Location(providerID: provider.id, path: "/" + name))
    #expect(try await reader.next() == Data("member".utf8))
  }

  @Test func isReadOnlyAndRejectsFolderReads() async throws {
    let (root, archive) = try await makeArchive()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let location = Location(providerID: provider.id, path: "/pkg/readme.txt")
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await provider.delete(location)
    }
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await provider.createDirectory(Location(providerID: provider.id, path: "/new"))
    }
    await #expect(throws: FileSystemError.unsupportedOperation) {
      _ = try await provider.read(Location(providerID: provider.id, path: "/pkg"))
    }
    await #expect(throws: FileSystemError.notFound) {
      _ = try await provider.stat(Location(providerID: provider.id, path: "/missing"))
    }
  }

  @Test func searchFindsFilesInsideAnArchive() async throws {
    let (root, archive) = try await makeArchive()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let query = SearchQuery(text: "needle", matchContents: true)
    let results = try await BuiltInSearch.run(
      query, in: Location(providerID: provider.id, path: "/"), provider: provider)
    #expect(results.map(\.name) == ["é[1].txt"])
  }

  @Test func goUpFromTheArchiveRootLeadsToTheContainingFolder() async throws {
    let (root, archive) = try await makeArchive()
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = ArchiveProvider(archive: archive)
    try await provider.load()
    let registry = ProviderRegistry(providers: [provider])
    let container = Location(providerID: "local", path: root.path)
    registry.setContainer(container, for: provider.id)
    let pane = await PaneModel(registry: registry)
    await pane.navigate(to: Location(providerID: provider.id, path: "/"))
    #expect(await pane.parentLocation == container)
    #expect(await pane.canGoUp)
    registry.unregister(id: provider.id)
    #expect(registry.container(of: provider.id) == nil)
  }
}
