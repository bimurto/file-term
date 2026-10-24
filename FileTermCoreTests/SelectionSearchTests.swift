import Foundation
import Testing

@testable import FileTermCore

private func entry(_ name: String, kind: FileEntry.Kind = .file, tags: [String] = []) -> FileEntry {
  FileEntry(
    location: Location(providerID: "local", path: "/t/" + name), name: name, kind: kind,
    tags: tags)
}

struct SelectionOpsTests {
  let entries = [
    entry("a.txt"), entry("b.md", tags: ["Red"]), entry("Report.TXT"), entry("dir", kind: .directory),
  ]

  @Test func invertSwapsSelectedAndUnselected() {
    let selected: Set<Location> = [entries[0].id, entries[1].id]
    let inverted = SelectionOps.invert(all: entries, selected: selected)
    #expect(inverted == [entries[2].id, entries[3].id])
    #expect(SelectionOps.invert(all: entries, selected: inverted) == selected)
  }

  @Test func quickSelectMatchesNameExtensionAndTag() {
    let current: Set<Location> = [entries[3].id]
    let name = QuickSelectCriteria(field: .name, pattern: "re")
    #expect(name.preview(entries: entries, current: current).matched == 1)
    let wildcard = QuickSelectCriteria(field: .name, pattern: "*.txt")
    #expect(wildcard.preview(entries: entries, current: []).matched == 2)
    let ext = QuickSelectCriteria(field: .fileExtension, pattern: ".txt")
    #expect(ext.preview(entries: entries, current: []).resulting == [entries[0].id, entries[2].id])
    let tag = QuickSelectCriteria(field: .tag, pattern: "red")
    #expect(tag.preview(entries: entries, current: []).resulting == [entries[1].id])
  }

  @Test func addAndRemoveModes() {
    let current: Set<Location> = [entries[3].id, entries[0].id]
    var criteria = QuickSelectCriteria(field: .fileExtension, pattern: "txt", mode: .add)
    #expect(criteria.preview(entries: entries, current: current).resulting.count == 3)
    criteria.mode = .remove
    #expect(criteria.preview(entries: entries, current: current).resulting == [entries[3].id])
    criteria.mode = .replace
    #expect(criteria.preview(entries: entries, current: current).resulting.count == 2)
  }

  @Test func emptyPatternMatchesNothing() {
    #expect(QuickSelectCriteria(pattern: "").preview(entries: entries, current: []).matched == 0)
  }
}

@MainActor struct PaneSelectionTests {
  private func makeTree() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ft-" + UUID().uuidString)
    let sub = root.appendingPathComponent("sub")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try "hello needle".write(
      to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)
    try "x".write(to: root.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
    try "nested".write(
      to: sub.appendingPathComponent("needle.log"), atomically: true, encoding: .utf8)
    return root
  }

  @Test func selectionNeverChangesLocationAndInvertWorks() async throws {
    let root = try makeTree()
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    let location = provider.location(for: root)
    await pane.navigate(to: location)
    pane.selectAll()
    #expect(pane.selection.count == pane.entries.count)
    pane.invertSelection()
    #expect(pane.selection.isEmpty)
    pane.applyQuickSelect(QuickSelectCriteria(field: .fileExtension, pattern: "txt"))
    #expect(pane.selection.count == 1)
    #expect(pane.location == location)
    pane.deselectAll()
    #expect(pane.selection.isEmpty)
  }

  @Test func showHiddenAndRefresh() async throws {
    let root = try makeTree()
    let provider = LocalFileSystemProvider()
    let prefs = ViewPreferences()
    let pane = PaneModel(providers: [provider], viewPreferences: prefs)
    await pane.navigate(to: provider.location(for: root))
    #expect(!pane.entries.contains { $0.name == ".secret" })
    prefs.showHidden = true
    await pane.refresh()
    #expect(pane.entries.first { $0.name == ".secret" }?.isHidden == true)
    pane.selection = [pane.entries[0].id]
    try "y".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    await pane.refresh()
    #expect(pane.entries.contains { $0.name == "new.txt" })
    #expect(pane.selection.count == 1)
  }

  @Test func searchOpensSeparateScopeAndCloseReturnsToFolder() async throws {
    let root = try makeTree()
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    let location = provider.location(for: root)
    await pane.navigate(to: location)
    pane.selection = [pane.entries[0].id]
    let folderCount = pane.entries.count
    await pane.search(SearchQuery(text: "needle", includeSubfolders: true))
    #expect(pane.searchScope?.results.map(\.name) == ["needle.log"])
    #expect(pane.location == location)
    pane.selectAll()
    #expect(pane.selectedEntries.count == 1)
    pane.closeSearch()
    #expect(pane.searchScope == nil)
    #expect(pane.entries.count == folderCount)
    #expect(pane.selection.count == 1)
  }

  @Test func searchOptionsSubfoldersAndContents() async throws {
    let root = try makeTree()
    let provider = LocalFileSystemProvider()
    let top = provider.location(for: root)
    let flat = try await BuiltInSearch.run(
      SearchQuery(text: "needle", includeSubfolders: false), in: top, provider: provider)
    #expect(flat.isEmpty)
    let contents = try await BuiltInSearch.run(
      SearchQuery(text: "needle", matchContents: true, includeSubfolders: false), in: top,
      provider: provider)
    #expect(contents.map(\.name) == ["notes.txt"])
    let ext = try await BuiltInSearch.run(
      SearchQuery(text: "log", matchName: false, matchExtension: true), in: top,
      provider: provider)
    #expect(ext.map(\.name) == ["needle.log"])
  }

  @Test func spotlightUnavailableForRemote() {
    let remote = Location(providerID: "sftp", path: "/x")
    #expect(!SearchEngine.spotlight.isAvailable(for: remote))
    #expect(SearchEngine.builtIn.isAvailable(for: remote))
    #expect(SearchEngine.spotlight.isAvailable(for: Location(providerID: "local", path: "/")))
  }
}

@MainActor struct QuickOpenAndShortcutTests {
  @Test func fuzzyRanking() {
    #expect(FuzzyMatcher.score("nf", "New Folder")! > FuzzyMatcher.score("nf", "Show Info Panel")!)
    #expect(FuzzyMatcher.score("xyz", "New Folder") == nil)
    let exact = FuzzyMatcher.score("back", "Back")!
    #expect(exact > FuzzyMatcher.score("back", "Go Back Home Now")!)
  }

  @Test func searchesAcrossSourcesAndRunsCommand() {
    var ran = false
    let commands = ClosureQuickOpenSource {
      [QuickOpenItem(id: "c", title: "Refresh", kind: .command) { ran = true }]
    }
    let folders = ClosureQuickOpenSource {
      [QuickOpenItem(id: "f", title: "Documents", subtitle: "/Users/x", kind: .recent) {}]
    }
    let hits = QuickOpen.search("ref", sources: [commands, folders])
    #expect(hits.map(\.id) == ["c"])
    hits[0].perform()
    #expect(ran)
    #expect(QuickOpen.search("doc", sources: [commands, folders]).first?.kind == .recent)
  }

  @Test func defaultsConflictsAndRestore() {
    var map = ShortcutMap(defaults: [
      "select.quick": DefaultShortcuts.quickSelect, "quickOpen": DefaultShortcuts.quickOpen,
      "file.open": DefaultShortcuts.open,
    ])
    #expect(map.effective(for: "quickOpen")?.display == "⎋")
    #expect(map.effective(for: "select.quick")?.display == "⌘S")
    let ids = ["select.quick", "quickOpen", "file.open"]
    #expect(
      map.conflicts(for: DefaultShortcuts.open, excluding: "select.quick", among: ids) == [
        "file.open"
      ])
    map.assign(DefaultShortcuts.open, to: "select.quick")
    #expect(map.isCustomized("select.quick"))
    map.assign(nil, to: "file.open")
    #expect(map.effective(for: "file.open") == nil)
    map.restoreDefaults()
    #expect(map.effective(for: "file.open") == DefaultShortcuts.open)
    #expect(map.overrides.isEmpty)
  }

  @Test func overridesRoundTripThroughCodable() throws {
    let map = ShortcutMap(
      defaults: ["a": Shortcut(key: "a", command: true)],
      overrides: ["a": ShortcutOverride(shortcut: nil)])
    let data = try JSONEncoder().encode(map.overrides)
    let decoded = try JSONDecoder().decode([String: ShortcutOverride].self, from: data)
    #expect(ShortcutMap(defaults: map.defaults, overrides: decoded).effective(for: "a") == nil)
  }
}
