import Foundation
import Testing

@testable import FileTermCore

@MainActor struct PresentationTests {
  private func entry(_ name: String, size: Int64? = nil, tags: [String] = []) -> FileEntry {
    FileEntry(
      location: Location(providerID: "local", path: "/" + name), name: name,
      kind: .file, size: size, tags: tags)
  }

  @Test(arguments: FileSortField.allCases)
  func everySortFieldUsesItsMetadata(_ field: FileSortField) {
    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)
    let first = FileEntry(
      location: Location(providerID: "local", path: "/z.txt"), name: "z.txt", kind: .file,
      size: 2, createdAt: early, modifiedAt: early, addedAt: early, openedAt: early, tags: ["A"],
      owner: "alice", group: "alpha", permissions: 0o644)
    let second = FileEntry(
      location: Location(providerID: "local", path: "/a.zip"), name: "a.zip", kind: .file,
      size: 10, createdAt: late, modifiedAt: late, addedAt: late, openedAt: late, tags: ["Z"],
      owner: "zoe", group: "omega", permissions: 0o755)
    let expected = field == .name ? [second.id, first.id] : [first.id, second.id]
    #expect([second, first].sorted(using: EntryOrder(field: field)).map(\.id) == expected)
    #expect(
      [first, second].sorted(using: EntryOrder(field: field, order: .reverse)).map(\.id)
        == expected.reversed())
  }

  @Test func sortsNaturallyAndLeavesUnknownMetadataLastInEitherDirection() {
    let entries = [entry("file10", size: 10), entry("file2", size: 2), entry("unknown")]
    #expect(
      entries.sorted(using: EntryOrder(field: .name)).map(\.name) == ["file2", "file10", "unknown"])
    #expect(
      entries.sorted(using: EntryOrder(field: .size, order: .reverse)).map(\.name) == [
        "file10", "file2", "unknown",
      ])
    #expect(
      entries.sorted(using: EntryOrder(field: .size)).map(\.name) == ["file2", "file10", "unknown"])
  }

  @Test func groupsContainSortedMembersAndTagsCanAppearInSeveralSections() {
    let entries = [
      entry("z", tags: ["Work", "Blue"]), entry("a", tags: ["Work"]), entry("untagged"),
    ]
    let groups = EntryGrouping.groups(entries, by: .tags, order: EntryOrder(field: .name))
    #expect(groups.first { $0.title == "Work" }?.entries.map(\.name) == ["a", "z"])
    #expect(groups.first { $0.title == "Blue" }?.entries.map(\.name) == ["z"])
    #expect(groups.first { $0.title == "No Tags" }?.entries.map(\.name) == ["untagged"])
  }

  @Test func viewOptionsSavedBeforeTheIconSizeOptionStillDecode() throws {
    let saved = #"{"mode":"Icons","sortField":"Size","descending":true,"groupField":"None"}"#
    let options = try JSONDecoder().decode(ViewOptions.self, from: Data(saved.utf8))
    #expect(options.mode == .icons)
    #expect(options.sortField == .size)
    #expect(!options.showsIconSize)
  }

  @Test func iconSizeOptionSurvivesARoundTrip() throws {
    var options = ViewOptions()
    options.showsIconSize = true
    let data = try JSONEncoder().encode(options)
    #expect(try JSONDecoder().decode(ViewOptions.self, from: data).showsIconSize)
  }

  @Test func folderAndTabViewOptionsHaveExplicitIndependentScopes() async {
    let preferences = ViewPreferences()
    let provider = LocalFileSystemProvider()
    let first = PaneModel(providers: [provider], viewPreferences: preferences)
    let second = PaneModel(providers: [provider], viewPreferences: preferences)
    let location = provider.location(for: FileManager.default.temporaryDirectory)
    await first.navigate(to: location)
    await second.navigate(to: location)
    first.viewOptions.mode = .icons
    #expect(second.viewOptions.mode == .list)
    first.viewScope = .folder
    first.viewOptions.sortField = .size
    second.viewScope = .folder
    #expect(second.viewOptions.sortField == .size)
    first.saveViewSettingsAsDefaults()
    #expect(preferences.defaults.sortField == .size)
    first.viewOptions.sortField = .name
    first.restoreDefaultViewSettings()
    #expect(first.viewOptions.sortField == .size)
  }
}
