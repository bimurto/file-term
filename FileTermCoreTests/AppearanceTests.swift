import Foundation
import Testing

@testable import FileTermCore

struct AppearanceTests {
  @Test func themesLoadFromDataFilesInOrderAndBadFilesAreSkipped() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let second = folder.appendingPathComponent("second.json")
    try Data(##"{"id":"b","name":"B","order":2,"appearance":"dark","accent":"#112233"}"##.utf8)
      .write(to: second)
    let first = folder.appendingPathComponent("first.json")
    try Data(#"{"id":"a","name":"A","order":1,"appearance":"system"}"#.utf8).write(to: first)
    let broken = folder.appendingPathComponent("broken.json")
    try Data("not a theme".utf8).write(to: broken)
    let themes = AppTheme.load(from: [second, broken, first])
    #expect(themes.map(\.id) == ["a", "b"])
    #expect(themes[1].appearance == .dark)
    #expect(themes[1].accent == "#112233")
    #expect(themes[0].background == nil)
  }

  @Test func terminalThemesLoadInOrderAndIncompleteFilesAreSkipped() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func write(_ name: String, order: Int = 1, foreground: String = "#FFFFFF", ansi: Int = 16)
      throws -> URL
    {
      let theme = TerminalTheme(
        id: name, name: name, order: order, foreground: foreground, background: "#000000",
        cursor: "#FFFFFF", selection: "#333333", ansi: Array(repeating: "#112233", count: ansi))
      let url = folder.appendingPathComponent("\(name).terminaltheme")
      try JSONEncoder().encode(theme).write(to: url)
      return url
    }
    let garbage = folder.appendingPathComponent("garbage.terminaltheme")
    try Data("not a theme".utf8).write(to: garbage)
    let urls = [
      try write("second", order: 2), try write("first", order: 1),
      try write("short", ansi: 15), try write("long", ansi: 17),
      try write("badColor", foreground: "white"), garbage,
    ]
    #expect(TerminalTheme.load(from: urls).map(\.id) == ["first", "second"])
  }

  @Test func aMissingTerminalThemeMeansTheSystemColors() {
    let theme = TerminalTheme(
      id: "a", name: "A", foreground: "#FFFFFF", background: "#000000", cursor: "#FFFFFF",
      selection: "#333333", ansi: [])
    #expect(TerminalTheme.theme(id: "a", in: [theme]) == theme)
    #expect(TerminalTheme.theme(id: "gone", in: [theme]) == nil)
    #expect(TerminalTheme.theme(id: nil, in: [theme]) == nil)
  }

  @Test func anUnknownThemeFallsBackToDefault() {
    let themes = [AppTheme(id: "dark", name: "Dark"), AppTheme(id: "default", name: "Default")]
    #expect(AppTheme.theme(id: "dark", in: themes).id == "dark")
    #expect(AppTheme.theme(id: "gone", in: themes).id == "default")
    #expect(AppTheme.theme(id: "gone", in: []) == .fallback)
    #expect(AppTheme.fallback.appearance == .system)
  }

  @Test func hexColorsParseAndMalformedOnesAreRejected() throws {
    let color = try #require(AppTheme.components(hex: "#FF0080"))
    #expect(color.red == 1)
    #expect(color.green == 0)
    #expect(abs(color.blue - 128.0 / 255) < 0.001)
    for bad in ["FF0080", "#FF00", "#GGGGGG", ""] { #expect(AppTheme.components(hex: bad) == nil) }
  }

  @Test func theDefaultTagsMatchTheGuide() {
    #expect(
      FileTag.defaults.map(\.name) == [
        "Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange",
      ]
    )
    #expect(FileTag.defaults.allSatisfy { $0.name == $0.color.title })
  }

  @Test func addingATagRejectsBlankAndDuplicateNames() throws {
    let tags = [FileTag(name: "Red", color: .red)]
    let added = try #require(FileTag.adding("  Work ", color: .blue, to: tags))
    #expect(added.last == FileTag(name: "Work", color: .blue))
    #expect(FileTag.adding("   ", color: .blue, to: tags) == nil)
    #expect(FileTag.adding("red", color: .blue, to: tags) == nil)
  }

  @Test func aTagMatchesWholeNamesOnly() {
    func entry(_ tags: [String]) -> FileEntry {
      FileEntry(
        location: Location(providerID: "local", path: "/a"), name: "a", kind: .file, tags: tags)
    }
    let red = FileTag(name: "Red", color: .red)
    #expect(red.isOn(entry(["Red"])))
    #expect(red.isOn(entry(["red\n6"])))
    #expect(!red.isOn(entry(["Infrared"])))
    #expect(!red.isOn(entry([])))
  }

  @Test func aDropLeavesOutItemsThatCannotGoThere() {
    let paths = ["/a/file", "/b/file", "/b/folder", "/b/folder/inner", "/b/other"]
    #expect(FileDrop.sources(paths, into: "/b/folder") == ["/a/file", "/b/file", "/b/other"])
    #expect(FileDrop.sources(["/b"], into: "/b/folder/inner").isEmpty)
    #expect(FileDrop.sources(["/b/folder2"], into: "/b/folder") == ["/b/folder2"])
  }

  @Test func aDropMovesOnTheSameVolumeUnlessOptionIsHeld() {
    #expect(FileDrop.movesByDefault(sameVolume: true, optionPressed: false))
    #expect(!FileDrop.movesByDefault(sameVolume: true, optionPressed: true))
    #expect(!FileDrop.movesByDefault(sameVolume: false, optionPressed: false))
  }

  @Test func releasesCompareNumerically() throws {
    let page = try #require(URL(string: "https://example.com/r"))
    #expect(AppRelease(tag: "v0.10.0", page: page).isNewer(than: "0.9.0"))
    #expect(AppRelease(tag: "1.0", page: page).isNewer(than: "0.9.9"))
    #expect(!AppRelease(tag: "v0.1.0", page: page).isNewer(than: "0.1.0"))
    #expect(!AppRelease(tag: "v0.1.0", page: page).isNewer(than: "0.2.0"))
    let decoded = try JSONDecoder().decode(
      AppRelease.self,
      from: Data(#"{"tag_name":"v2.0.0","html_url":"https://example.com/r","id":1}"#.utf8))
    #expect(decoded == AppRelease(tag: "v2.0.0", page: page))
    #expect(decoded.version == "2.0.0")
  }

  @Test func theMissingPermissionDependsOnTheFolder() {
    let home = "/Users/me"
    for path in ["/Users/me/Desktop", "/Users/me/Documents/a", "/Users/me/Downloads", "/Volumes/X"]
    {
      #expect(SystemPermission.required(forPath: path, home: home) == .filesAndFolders)
    }
    for path in ["/Users/me/Library/Mail", "/Users/me/DesktopNotes", "/private/var/db"] {
      #expect(SystemPermission.required(forPath: path, home: home) == .fullDiskAccess)
    }
  }

  @MainActor @Test func aPaneRemembersWhichFolderWasDenied() async {
    let pane = PaneModel(registry: ProviderRegistry(providers: [DenyingProvider()]))
    let denied = Location(providerID: "local", path: "/secret")
    await pane.navigate(to: denied)
    #expect(pane.deniedLocation == denied)
    await pane.navigate(to: Location(providerID: "local", path: "/open"))
    #expect(pane.deniedLocation == nil)
  }

  @MainActor @Test func aSearchCanStartFromAnotherRoot() async {
    let pane = PaneModel(registry: ProviderRegistry(providers: [DenyingProvider()]))
    let open = Location(providerID: "local", path: "/open")
    await pane.navigate(to: open)
    let root = Location(providerID: "local", path: "/other")
    await pane.search(SearchQuery(text: "x"), root: root)
    #expect(pane.searchScope?.root == root)
    #expect(pane.location == open)
    await pane.search(SearchQuery(text: "y"))
    #expect(pane.searchScope?.root == root)
  }
}

private struct DenyingProvider: FileSystemProvider {
  let id = "local"
  func list(_ location: Location) async throws -> [FileEntry] {
    if location.path == "/secret" { throw FileSystemError.permissionDenied }
    return []
  }
  func stat(_ location: Location) async throws -> FileEntry { throw FileSystemError.notFound }
  func read(_ location: Location) async throws -> any FileByteReader {
    throw FileSystemError.notFound
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {}
  func move(_ source: Location, to destination: Location) async throws {}
  func delete(_ location: Location) async throws {}
}
