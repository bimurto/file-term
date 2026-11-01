import Foundation
import Testing

@testable import FileTermCore

struct SyncTests {
  private struct Trees {
    let left: URL
    let right: URL
    let registry = ProviderRegistry(providers: [LocalFileSystemProvider()])
    var leftLocation: Location { Location(providerID: "local", path: left.path) }
    var rightLocation: Location { Location(providerID: "local", path: right.path) }

    init() throws {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      left = root.appendingPathComponent("left")
      right = root.appendingPathComponent("right")
      try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(
      _ side: URL, _ path: String, _ text: String = "x",
      modified: Date = Date(timeIntervalSince1970: 1_000_000)
    ) throws -> URL {
      let url = side.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
      return url
    }

    func analyze(_ options: SyncOptions) async throws -> [SyncAction] {
      try await SyncAnalyzer.analyze(
        left: leftLocation, right: rightLocation, options: options, registry: registry)
    }
  }

  private func summary(_ actions: [SyncAction]) -> [String] {
    actions.map { "\($0.kind.rawValue):\($0.towards.rawValue):\($0.relativePath)" }
  }

  @Test func addsMissingItemsAndNothingElseByDefault() async throws {
    let t = try Trees()
    try t.file(t.left, "a.txt")
    try t.file(t.left, "sub/b.txt")
    try t.file(t.right, "only-right.txt")
    let actions = try await t.analyze(SyncOptions())
    #expect(summary(actions) == ["add:right:a.txt", "add:right:sub", "add:right:sub/b.txt"])
  }

  @Test func deleteOrphansIsOffByDefaultAndProposesDeletesWhenOn() async throws {
    let t = try Trees()
    try t.file(t.right, "orphan.txt")
    #expect(SyncOptions().deleteOrphans == false)
    #expect(try await t.analyze(SyncOptions()).isEmpty)
    var options = SyncOptions()
    options.deleteOrphans = true
    #expect(summary(try await t.analyze(options)) == ["delete:right:orphan.txt"])
  }

  @Test func anOrphanFolderHoldingWhatTheScanLeftOutIsKept() async throws {
    let t = try Trees()
    try t.file(t.right, "old/visible.txt")
    try t.file(t.right, "old/.secret")
    try t.file(t.right, "excluded/visible.txt")
    try t.file(t.right, "excluded/keep.log")
    try t.file(t.right, "deep/inner/visible.txt")
    try t.file(t.right, "deep/inner/.secret")
    try t.file(t.right, "linked/visible.txt")
    try FileManager.default.createSymbolicLink(
      at: t.right.appendingPathComponent("linked/link"),
      withDestinationURL: t.right.appendingPathComponent("old"))
    try t.file(t.right, "clean/visible.txt")
    var options = SyncOptions()
    options.deleteOrphans = true
    options.excludes = [SyncFilter(pattern: "*.log")]
    #expect(
      Set(summary(try await t.analyze(options))) == [
        "delete:right:clean",
        "delete:right:old/visible.txt",
        "delete:right:excluded/visible.txt",
        "delete:right:deep/inner/visible.txt",
        "delete:right:linked/visible.txt",
      ])
  }

  @Test func withHiddenItemsOnAnOrphanFolderIsOneDelete() async throws {
    let t = try Trees()
    try t.file(t.right, "old/.secret")
    var options = SyncOptions()
    options.deleteOrphans = true
    options.hidden = true
    #expect(summary(try await t.analyze(options)) == ["delete:right:old"])
  }

  @Test func orphanFolderIsOneDeleteWithoutItsChildren() async throws {
    let t = try Trees()
    try t.file(t.right, "old/a.txt")
    try t.file(t.right, "old/deep/b.txt")
    var options = SyncOptions()
    options.deleteOrphans = true
    #expect(summary(try await t.analyze(options)) == ["delete:right:old"])
  }

  @Test func unreadableSubfolderStopsTheAnalysisInsteadOfProposingDeletes() async throws {
    let t = try Trees()
    try t.file(t.left, "sub/a.txt")
    try t.file(t.right, "sub/keep.txt")
    let unreadable = t.left.appendingPathComponent("sub")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: unreadable.path)
    }
    var options = SyncOptions()
    options.deleteOrphans = true
    await #expect(throws: SyncError.self) { try await t.analyze(options) }
    // Excluding the folder is the way past it: it is not entered, so nothing is left to read.
    options.excludes = [SyncFilter(pattern: "sub")]
    try t.file(t.right, "orphan.txt")
    #expect(summary(try await t.analyze(options)) == ["delete:right:orphan.txt"])
  }

  @Test func updatesWhenDestinationIsOlderOrSizeDiffers() async throws {
    let t = try Trees()
    let old = Date(timeIntervalSince1970: 1_000_000)
    let new = Date(timeIntervalSince1970: 2_000_000)
    try t.file(t.left, "newer.txt", modified: new)
    try t.file(t.right, "newer.txt", modified: old)
    try t.file(t.left, "size.txt", "long text", modified: old)
    try t.file(t.right, "size.txt", "x", modified: old)
    try t.file(t.left, "same.txt", modified: old)
    try t.file(t.right, "same.txt", modified: old)
    #expect(summary(try await t.analyze(SyncOptions())) == ["update:right:newer.txt"])
    var options = SyncOptions()
    options.updateWhenOlder = false
    options.updateWhenSizeDiffers = true
    #expect(summary(try await t.analyze(options)) == ["update:right:size.txt"])
  }

  @Test func timeOffsetAndToleranceAreApplied() async throws {
    let t = try Trees()
    let base = Date(timeIntervalSince1970: 1_000_000)
    try t.file(t.left, "a.txt", modified: base.addingTimeInterval(3600))
    try t.file(t.right, "a.txt", modified: base)
    try t.file(t.left, "close.txt", modified: base.addingTimeInterval(1))
    try t.file(t.right, "close.txt", modified: base)
    #expect(summary(try await t.analyze(SyncOptions())) == ["update:right:a.txt"])
    var options = SyncOptions()
    options.timeOffset = 1
    options.offsetUnit = .hours
    #expect(try await t.analyze(options).isEmpty)
  }

  @Test func rightToLeftMirrorsTheRules() async throws {
    let t = try Trees()
    try t.file(t.right, "r.txt")
    try t.file(t.left, "l.txt")
    var options = SyncOptions()
    options.direction = .rightToLeft
    options.deleteOrphans = true
    #expect(summary(try await t.analyze(options)) == ["delete:left:l.txt", "add:left:r.txt"])
  }

  @Test func hiddenItemsSubfoldersAndEmptyFoldersFollowTheOptions() async throws {
    let t = try Trees()
    try t.file(t.left, ".hidden")
    try t.file(t.left, "sub/a.txt")
    try FileManager.default.createDirectory(
      at: t.left.appendingPathComponent("empty"), withIntermediateDirectories: true)
    #expect(
      summary(try await t.analyze(SyncOptions())) == [
        "add:right:empty", "add:right:sub", "add:right:sub/a.txt",
      ])
    var options = SyncOptions()
    options.hidden = true
    options.skipEmptyFolders = true
    #expect(
      summary(try await t.analyze(options)) == [
        "add:right:.hidden", "add:right:sub", "add:right:sub/a.txt",
      ])
    options.subfolders = false
    #expect(summary(try await t.analyze(options)) == ["add:right:.hidden"])
    options.addItems = false
    #expect(try await t.analyze(options).isEmpty)
  }

  @Test func globAndRegexExclusions() async throws {
    let t = try Trees()
    try t.file(t.left, "keep.txt")
    try t.file(t.left, "skip.log")
    try t.file(t.left, "node_modules/x.js")
    try t.file(t.left, "docs/a.tmp")
    var options = SyncOptions()
    options.excludes = [
      SyncFilter(pattern: "*.log"), SyncFilter(pattern: "node_modules"),
      SyncFilter(pattern: "\\.tmp$", isRegex: true),
    ]
    #expect(
      summary(try await t.analyze(options)) == ["add:right:docs", "add:right:keep.txt"])
    options.excludes = [SyncFilter(pattern: "(", isRegex: true)]
    await #expect(throws: SyncError.self) { try await t.analyze(options) }
  }

  @Test func bothWaysLetsTheNewerSideWinAndReportsTrueConflicts() async throws {
    let t = try Trees()
    let old = Date(timeIntervalSince1970: 1_000_000)
    let new = Date(timeIntervalSince1970: 2_000_000)
    try t.file(t.left, "l-newer.txt", modified: new)
    try t.file(t.right, "l-newer.txt", modified: old)
    try t.file(t.left, "r-newer.txt", modified: old)
    try t.file(t.right, "r-newer.txt", modified: new)
    try t.file(t.left, "only-left.txt")
    try t.file(t.right, "only-right.txt")
    try t.file(t.left, "clash.txt", "longer", modified: old)
    try t.file(t.right, "clash.txt", "x", modified: old)
    var options = SyncOptions()
    options.direction = .bothWays
    options.updateWhenSizeDiffers = true
    options.deleteOrphans = true
    let actions = try await t.analyze(options)
    #expect(
      summary(actions) == [
        "conflict:right:clash.txt", "update:right:l-newer.txt", "add:right:only-left.txt",
        "add:left:only-right.txt", "update:left:r-newer.txt",
      ])
    #expect(actions.first { $0.kind == .conflict }?.isChecked == false)
  }

  @Test func fileAgainstFolderIsAnUncheckedUnrunnableConflict() async throws {
    let t = try Trees()
    try t.file(t.left, "thing")
    try FileManager.default.createDirectory(
      at: t.right.appendingPathComponent("thing"), withIntermediateDirectories: true)
    let actions = try await t.analyze(SyncOptions())
    #expect(actions.count == 1)
    #expect(actions[0].kind == .conflict && !actions[0].isChecked && !actions[0].isRunnable)
  }

  @Test func runnerOrdersFoldersThenFilesThenDeepestDeletesAndSkipsUnchecked() async throws {
    func action(_ path: String, _ kind: SyncAction.Kind, dir: Bool = false, checked: Bool = true)
      -> SyncAction
    {
      SyncAction(
        relativePath: path, kind: kind, towards: .right, isDirectory: dir, left: nil, right: nil,
        isChecked: checked)
    }
    let log = Log()
    let summary = try await SyncRunner.run(
      actions: [
        action("old", .delete, dir: true), action("old/x.txt", .delete),
        action("a/b/c.txt", .add), action("a/b", .add, dir: true), action("a", .add, dir: true),
        action("skipped.txt", .add, checked: false),
      ],
      control: TransferControl(),
      makeFolder: { await log.add("mkdir \($0.relativePath)") },
      copy: { await log.add("copy \($0.relativePath)") },
      delete: { await log.add("delete \($0.relativePath)") })
    #expect(
      await log.lines == [
        "mkdir a", "mkdir a/b", "copy a/b/c.txt", "delete old/x.txt", "delete old",
      ])
    #expect(summary.succeeded == 5)
  }

  @Test func runnerReportsPartialFailureAndHonoursCancellation() async throws {
    struct Boom: Error {}
    let adds = [
      SyncAction(
        relativePath: "a", kind: .add, towards: .right, isDirectory: false, left: nil, right: nil),
      SyncAction(
        relativePath: "b", kind: .add, towards: .right, isDirectory: false, left: nil, right: nil),
    ]
    await #expect(throws: PartialTransferError.self) {
      try await SyncRunner.run(
        actions: adds, control: TransferControl(), makeFolder: { _ in },
        copy: { if $0.relativePath == "b" { throw Boom() } }, delete: { _ in })
    }
    let control = TransferControl()
    await control.cancel()
    await #expect(throws: CancellationError.self) {
      try await SyncRunner.run(
        actions: adds, control: control, makeFolder: { _ in }, copy: { _ in }, delete: { _ in })
    }
  }

  // MARK: Names a case-insensitive disk sees as one item

  private func entry(_ path: String, _ kind: FileEntry.Kind = .file) -> FileEntry {
    FileEntry(
      location: Location(providerID: "local", path: "/" + path),
      name: (path as NSString).lastPathComponent, kind: kind, size: 1)
  }

  @Test func addsDifferingOnlyInCaseAreRefused() {
    let actions = SyncAnalyzer.compare(
      left: ["Foo": entry("Foo"), "foo": entry("foo"), "other": entry("other")], right: [:],
      options: SyncOptions())
    let refused = actions.filter { !$0.isRunnable }
    #expect(Set(refused.map(\.relativePath)) == ["Foo", "foo"])
    #expect(refused.allSatisfy { $0.kind == .conflict && !$0.isChecked })
    #expect(actions.first { $0.relativePath == "other" }?.kind == .add)
  }

  @Test func anAddClashingWithAnExistingNameIsRefusedWithItsOrphanDelete() {
    var options = SyncOptions()
    options.deleteOrphans = true
    let actions = SyncAnalyzer.compare(
      left: ["Foo": entry("Foo")], right: ["foo": entry("foo")], options: options)
    #expect(actions.count == 2)
    #expect(actions.allSatisfy { $0.kind == .conflict && !$0.isRunnable })
  }

  @Test func itemsInsideAClashingFolderAreRefused() {
    let actions = SyncAnalyzer.compare(
      left: ["Foo": entry("Foo", .directory), "Foo/new.txt": entry("Foo/new.txt")],
      right: ["foo": entry("foo", .directory)], options: SyncOptions())
    #expect(actions.count == 2)
    #expect(actions.allSatisfy { !$0.isRunnable })
  }

  @Test func updatesOfMatchingNamesAreNotRefused() {
    let actions = SyncAnalyzer.compare(
      left: ["a.txt": entry("a.txt")], right: ["a.txt": entry("a.txt")],
      options: {
        var options = SyncOptions()
        options.updateWhenSizeDiffers = true
        return options
      }())
    #expect(actions.isEmpty)
  }

  @Test func anAddOntoALinkIsRefused() async throws {
    let trees = try Trees()
    try trees.file(trees.left, "a.txt")
    try trees.file(trees.left, "b.txt")
    let elsewhere = try trees.file(trees.right, "elsewhere.txt", "keep")
    try FileManager.default.createSymbolicLink(
      at: trees.right.appendingPathComponent("a.txt"), withDestinationURL: elsewhere)
    let actions = try await trees.analyze(SyncOptions())
    let row = try #require(actions.first { $0.relativePath == "a.txt" })
    #expect(row.kind == .conflict && !row.isRunnable && !row.isChecked)
    #expect(actions.first { $0.relativePath == "b.txt" }?.kind == .add)
  }

  @Test func localCopyKeepsTheModificationDateSoTheNextAnalysisIsClean() async throws {
    let t = try Trees()
    let date = Date(timeIntervalSince1970: 1_500_000)
    let source = try t.file(t.left, "a.txt", modified: date)
    let operations = LocalFileOperations()
    _ = try await operations.transfer(
      sources: [source], to: t.right, move: false,
      resolve: { _ in ConflictResolution(decision: .replace) })
    #expect(try await t.analyze(SyncOptions()).isEmpty)
    var options = SyncOptions()
    options.direction = .bothWays
    options.updateWhenSizeDiffers = true
    #expect(try await t.analyze(options).isEmpty)
  }
}

private actor Log {
  var lines: [String] = []
  func add(_ line: String) { lines.append(line) }
}

struct SyncFavoriteTests {
  @Test func favoriteKeepsRootsAndEveryOptionThroughCoding() throws {
    var options = SyncOptions()
    options.direction = .bothWays
    options.hidden = true
    options.skipEmptyFolders = true
    options.updateWhenSizeDiffers = true
    options.timeOffset = 2
    options.offsetUnit = .hours
    options.excludes = [SyncFilter(pattern: "*.log"), SyncFilter(pattern: "^tmp", isRegex: true)]
    let favorite = SyncFavorite(
      name: "Work", left: Location(providerID: "local", path: "/a"),
      right: Location(providerID: "sftp.1", path: "/b"), options: options)
    let decoded = try JSONDecoder().decode(
      SyncFavorite.self, from: JSONEncoder().encode(favorite))
    #expect(decoded == favorite)
    #expect(decoded.options.deleteOrphans == false)
  }
}
