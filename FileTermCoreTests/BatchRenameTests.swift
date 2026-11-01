import Foundation
import Testing

@testable import FileTermCore

struct BatchRenameTests {
  private func item(_ name: String, directory: Bool = false, modified: Date? = nil) -> RenameItem {
    RenameItem(
      location: Location(providerID: "local", path: "/x/" + name), name: name,
      isDirectory: directory, modifiedAt: modified)
  }

  private func names(_ items: [RenameItem], _ rules: [RenameRule]) -> [String] {
    BatchRenamePlanner.preview(items: items, rules: rules).map(\.proposed)
  }

  @Test func replaceTextOccurrencesAndCaseSensitivity() {
    var rule = RenameRule(kind: .replaceText)
    rule.find = "a"
    rule.replacement = "_"
    let items = [item("aAbA.txt")]
    #expect(names(items, [rule]) == ["__b_.txt"])
    rule.caseSensitive = true
    #expect(names(items, [rule]) == ["_AbA.txt"])
    rule.caseSensitive = false
    rule.occurrence = .first
    #expect(names(items, [rule]) == ["_AbA.txt"])
    rule.occurrence = .last
    #expect(names(items, [rule]) == ["aAb_.txt"])
    rule.find = ""
    #expect(names(items, [rule]) == ["aAbA.txt"])
  }

  @Test func applyToNameExtensionOrFullName() {
    var rule = RenameRule(kind: .changeCase)
    rule.caseStyle = .upper
    let items = [item("report.final.txt"), item("Makefile"), item("dir.d", directory: true)]
    #expect(names(items, [rule]) == ["REPORT.FINAL.txt", "MAKEFILE", "DIR.D"])
    rule.applyTo = .fileExtension
    #expect(names(items, [rule]) == ["report.final.TXT", "Makefile", "dir.d"])
    rule.applyTo = .fullName
    #expect(names(items, [rule]) == ["REPORT.FINAL.TXT", "MAKEFILE", "DIR.D"])
  }

  @Test func changeCaseStyles() {
    var rule = RenameRule(kind: .changeCase)
    let items = [item("hELLO wORLD.txt")]
    rule.caseStyle = .lower
    #expect(names(items, [rule]) == ["hello world.txt"])
    rule.caseStyle = .title
    #expect(names(items, [rule]) == ["Hello World.txt"])
    rule.caseStyle = .sentence
    #expect(names(items, [rule]) == ["Hello world.txt"])
  }

  @Test func sequenceFollowsTheShownOrderWithStepPaddingPrefixAndSuffix() {
    var rule = RenameRule(kind: .addSequence)
    let items = [item("sample-two.txt"), item("sample-one.txt")]
    #expect(names(items, [rule]) == ["1sample-two.txt", "2sample-one.txt"])
    rule.start = 5
    rule.step = 5
    rule.padding = 3
    rule.prefix = "#"
    rule.suffix = "_"
    rule.position = .end
    #expect(names(items, [rule]) == ["sample-two#005_.txt", "sample-one#010_.txt"])
    rule.position = .index
    rule.positionIndex = 2
    #expect(names(items, [rule]).first == "sa#005_mple-two.txt")
  }

  @Test func addTextAtPositionsAndOnTheExtension() {
    var rule = RenameRule(kind: .addText)
    rule.text = "X"
    let items = [item("ab.txt"), item("noext")]
    #expect(names(items, [rule]) == ["Xab.txt", "Xnoext"])
    rule.position = .end
    #expect(names(items, [rule]) == ["abX.txt", "noextX"])
    rule.position = .index
    rule.positionIndex = 99
    #expect(names(items, [rule]) == ["abX.txt", "noextX"])
    rule.applyTo = .fileExtension
    rule.text = "bak"
    #expect(names(items, [rule]) == ["ab.txtbak", "noext.bak"])
  }

  @Test func addDateUsesFileDateOrTheCurrentDate() {
    var rule = RenameRule(kind: .addDate)
    rule.position = .end
    rule.dateFormat = "_yyyyMMdd"
    let fileDate = Date(timeIntervalSince1970: 0)
    let now = Date(timeIntervalSince1970: 86_400 * 400)
    let items = [item("a.txt", modified: fileDate), item("b.txt")]
    let expectedFile = {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "_yyyyMMdd"
      return f.string(from: fileDate)
    }()
    #expect(names(items, [rule]) == ["a" + expectedFile + ".txt", "b.txt"])
    rule.dateSource = .now
    let rows = BatchRenamePlanner.preview(items: items, rules: [rule], now: now)
    #expect(rows[0].proposed.hasPrefix("a_") && rows[1].proposed.hasPrefix("b_"))
    #expect(rows[0].proposed.dropFirst() == rows[1].proposed.dropFirst())
  }

  @Test func rulesRunInOrder() {
    var replace = RenameRule(kind: .replaceText)
    replace.find = "old"
    replace.replacement = "new"
    var sequence = RenameRule(kind: .addSequence)
    sequence.position = .end
    var upper = RenameRule(kind: .changeCase)
    upper.caseStyle = .upper
    #expect(names([item("old.txt")], [replace, sequence, upper]) == ["NEW1.txt"])
    #expect(names([item("old.txt")], [upper, replace, sequence]) == ["new1.txt"])
    replace.caseSensitive = true
    #expect(names([item("old.txt")], [upper, replace, sequence]) == ["OLD1.txt"])
  }

  @Test func sequencerStagesSwapsAndCaseOnlyChanges() {
    var counter = 0
    let steps = RenameSequencer.steps(
      for: [("/d/a", "b"), ("/d/b", "a"), ("/d/c", "C"), ("/d/e", "f"), ("/d/same", "same")],
      temporaryName: {
        counter += 1
        return "t\(counter)"
      })
    #expect(
      steps == [
        RenameStep(path: "/d/a", name: "t1"), RenameStep(path: "/d/b", name: "t2"),
        RenameStep(path: "/d/c", name: "t3"), RenameStep(path: "/d/e", name: "f"),
        RenameStep(path: "/d/t1", name: "b"), RenameStep(path: "/d/t2", name: "a"),
        RenameStep(path: "/d/t3", name: "C"),
      ])
  }

  @Test func localBatchRenameHandlesSwapsAndUndoesAsOneStep() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let a = dir.appendingPathComponent("a.txt")
    let b = dir.appendingPathComponent("b.txt")
    let c = dir.appendingPathComponent("c.txt")
    try "A".write(to: a, atomically: true, encoding: .utf8)
    try "B".write(to: b, atomically: true, encoding: .utf8)
    try "C".write(to: c, atomically: true, encoding: .utf8)
    let operations = LocalFileOperations()
    let results = try await operations.renameBatch([(a, "b.txt"), (b, "a.txt"), (c, "C.txt")])
    #expect(results.map(\.lastPathComponent) == ["b.txt", "a.txt", "C.txt"])
    #expect(try String(contentsOf: a, encoding: .utf8) == "B")
    #expect(try String(contentsOf: b, encoding: .utf8) == "A")
    #expect(
      Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        == ["a.txt", "b.txt", "C.txt"])
    try await operations.undo()
    #expect(try String(contentsOf: a, encoding: .utf8) == "A")
    #expect(try String(contentsOf: b, encoding: .utf8) == "B")
    #expect(
      Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        == ["a.txt", "b.txt", "c.txt"])
  }

  @Test func localBatchRenameRefusesAnExistingNameAndInvalidNames() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let a = dir.appendingPathComponent("a.txt")
    try "A".write(to: a, atomically: true, encoding: .utf8)
    try "keep".write(
      to: dir.appendingPathComponent("taken.txt"), atomically: true, encoding: .utf8)
    let operations = LocalFileOperations()
    await #expect(throws: LocalFileOperationError.self) {
      try await operations.renameBatch([(a, "taken.txt")])
    }
    await #expect(throws: LocalFileOperationError.self) {
      try await operations.renameBatch([(a, "x/y")])
    }
    #expect(
      try String(contentsOf: dir.appendingPathComponent("taken.txt"), encoding: .utf8) == "keep")
  }

  @Test func validationFlagsDuplicatesInvalidNamesTakenNamesAndExtensionChanges() {
    func row(_ name: String, in folder: String = "/d") -> RenameItem {
      RenameItem(location: Location(providerID: "local", path: folder + "/" + name), name: name)
    }
    var text = RenameRule(kind: .replaceText)
    text.find = "a"
    text.replacement = "x"
    // a1 and A1 both become x1 (case-insensitive); "b.txt" -> "b.md" changes the extension.
    let items = [row("a1"), row("A1"), row("b.txt")]
    var rows = BatchRenamePlanner.preview(items: items, rules: [text])
    #expect(rows[0].issues == [.duplicateName] && rows[1].issues == [.duplicateName])
    #expect(rows[2].issues.isEmpty)
    var ext = RenameRule(kind: .replaceText)
    ext.find = "txt"
    ext.replacement = "md"
    ext.applyTo = .fullName
    rows = BatchRenamePlanner.preview(items: items, rules: [ext])
    #expect(rows[2].issues == [.extensionChanged] && rows[2].hasWarning && !rows[2].hasError)

    var bad = RenameRule(kind: .replaceText)
    bad.find = "b"
    bad.replacement = "a/b:"
    rows = BatchRenamePlanner.preview(items: [row("b.txt")], rules: [bad])
    #expect(rows[0].issues == [.invalidName] && rows[0].hasError)
    var empty = RenameRule(kind: .replaceText)
    empty.find = "b.txt"
    empty.applyTo = .fullName
    rows = BatchRenamePlanner.preview(items: [row("b.txt")], rules: [empty])
    #expect(rows[0].issues.contains(.invalidName))

    var taken = RenameRule(kind: .replaceText)
    taken.find = "one"
    taken.replacement = "two"
    let existing = ["/d": Set(["one", "Two", "three"])]
    rows = BatchRenamePlanner.preview(items: [row("one")], rules: [taken], existingNames: existing)
    #expect(rows[0].issues == [.nameExists])
    // Swapping is fine: the name is given up by the other item in the same batch.
    var swap = RenameRule(kind: .replaceText)
    swap.find = "one"
    swap.replacement = "Two"
    rows = BatchRenamePlanner.preview(
      items: [row("one"), row("Two")], rules: [swap], existingNames: existing)
    #expect(rows[0].issues.isEmpty || rows[0].issues == [.duplicateName])
    #expect(!rows[0].issues.contains(.nameExists))
    // Unchanged rows never show issues, and other folders are separate namespaces.
    rows = BatchRenamePlanner.preview(
      items: [row("a1", in: "/d"), row("a1", in: "/e")], rules: [text])
    #expect(rows.allSatisfy { $0.issues.isEmpty })
  }

  @Test func presetKeepsItsRulesThroughCoding() throws {
    var rule = RenameRule(kind: .addSequence)
    rule.padding = 3
    rule.position = .end
    let preset = RenamePreset(name: "Numbered", rules: [rule, RenameRule(kind: .changeCase)])
    let decoded = try JSONDecoder().decode(
      RenamePreset.self, from: JSONEncoder().encode(preset))
    #expect(decoded == preset)
  }

  @Test func aFailedLocalBatchRenamePutsEveryNameBack() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let a = dir.appendingPathComponent("a.txt")
    let b = dir.appendingPathComponent("b.txt")
    let c = dir.appendingPathComponent("c.txt")
    try "A".write(to: a, atomically: true, encoding: .utf8)
    try "B".write(to: b, atomically: true, encoding: .utf8)
    try "C".write(to: c, atomically: true, encoding: .utf8)
    try "T".write(to: dir.appendingPathComponent("taken.txt"), atomically: true, encoding: .utf8)
    let operations = LocalFileOperations()

    // The swap moves a and b to temporary names before c hits the taken name.
    await #expect(throws: LocalFileOperationError.self) {
      try await operations.renameBatch([(a, "b.txt"), (b, "a.txt"), (c, "taken.txt")])
    }

    #expect(
      Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        == ["a.txt", "b.txt", "c.txt", "taken.txt"])
    #expect(try String(contentsOf: a, encoding: .utf8) == "A")
    #expect(try String(contentsOf: b, encoding: .utf8) == "B")
    #expect(await operations.historyState().canUndo == false)
  }

  private actor FakeNames {
    var items: [String: String]
    let refused: String
    init(_ items: [String: String], refusing refused: String) {
      self.items = items
      self.refused = refused
    }
    func rename(_ step: RenameStep) throws {
      if step.name == refused { throw FileSystemError.destinationExists }
      let folder = (step.path as NSString).deletingLastPathComponent
      items[(folder as NSString).appendingPathComponent(step.name)] = items.removeValue(
        forKey: step.path)
    }
  }

  @Test func performPutsFinishedStepsBackWhenOneFails() async throws {
    let names = FakeNames(["/d/a": "A", "/d/b": "B", "/d/c": "C"], refusing: "bad")
    let steps = [
      RenameStep(path: "/d/a", name: "one"), RenameStep(path: "/d/b", name: "two"),
      RenameStep(path: "/d/c", name: "bad"),
    ]
    await #expect(throws: FileSystemError.destinationExists) {
      try await RenameSequencer.perform(steps, before: {}, rename: { try await names.rename($0) })
    }
    #expect(await names.items == ["/d/a": "A", "/d/b": "B", "/d/c": "C"])
  }

  @Test func performPutsFinishedStepsBackWhenCancelled() async throws {
    let names = FakeNames(["/d/a": "A", "/d/b": "B"], refusing: "bad")
    let steps = [RenameStep(path: "/d/a", name: "one"), RenameStep(path: "/d/b", name: "two")]
    let calls = Counter()
    let task = Task {
      try await RenameSequencer.perform(
        steps,
        before: {
          if await calls.next() == 2 { throw CancellationError() }
        }
      ) { step in
        try Task.checkCancellation()
        try await names.rename(step)
      }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await names.items == ["/d/a": "A", "/d/b": "B"])
  }

  @Test func performReportsWhatItCouldNotPutBack() async throws {
    let names = FakeNames(["/d/a": "A", "/d/b": "B"], refusing: "a")
    let steps = [RenameStep(path: "/d/a", name: "one"), RenameStep(path: "/d/b", name: "a")]
    do {
      try await RenameSequencer.perform(steps, before: {}, rename: { try await names.rename($0) })
      Issue.record("Expected a failure")
    } catch let error as PartialTransferError {
      #expect(error.message.contains("/d/one"))
    }
  }

  private actor Counter {
    var value = 0
    func next() -> Int {
      value += 1
      return value
    }
  }
}
