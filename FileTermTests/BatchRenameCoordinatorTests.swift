import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@Suite(.serialized)
@MainActor struct BatchRenameCoordinatorTests {
  private func folder(_ names: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for name in names { try Data(name.utf8).write(to: root.appendingPathComponent(name)) }
    return root
  }

  @Test func renameWithSeveralItemsOpensBatchRenameInsteadOfAnAlert() async throws {
    let root = try folder(["a.txt", "b.txt"])
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: provider.location(for: root)))
    let coordinator = FileOperationCoordinator()
    var opened = 0
    coordinator.onBatchRename = { _ in opened += 1 }
    pane.selection = Set(pane.entries.map(\.location))
    coordinator.startRename(pane, window: nil)
    #expect(opened == 1)
    pane.selection = [pane.entries[0].location]
    coordinator.startRename(pane, window: nil)
    #expect(opened == 1 && pane.renamingLocation == pane.entries[0].location)
  }

  @Test func modelPreviewsCountsAndSubmitsOnlyChangedItems() {
    func item(_ name: String) -> RenameItem {
      RenameItem(location: Location(providerID: "local", path: "/d/" + name), name: name)
    }
    var submitted: [(location: Location, name: String)] = []
    let model = BatchRenameModel(
      items: [item("sample-two.txt"), item("sample-one.txt"), item("x.txt")],
      rules: []
    ) { submitted = $0 }
    #expect(!model.canRename && model.changedCount == 0)
    model.addRule(.addSequence)
    #expect(model.rows.map(\.proposed) == ["1sample-two.txt", "2sample-one.txt", "3x.txt"])
    model.addRule(.changeCase)
    model.moveRule(model.rules[1].id, by: -1)
    #expect(model.rules.map(\.kind) == [.changeCase, .addSequence])
    model.removeRule(model.rules[0].id)
    model.rename()
    #expect(submitted.map(\.name) == ["1sample-two.txt", "2sample-one.txt", "3x.txt"])
  }

  @Test func submittedRenameRunsAsOneQueueJobAndSwapsNames() async throws {
    let root = try folder(["a.txt", "b.txt"])
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: provider.location(for: root)))
    let coordinator = FileOperationCoordinator()
    let a = provider.location(for: root.appendingPathComponent("a.txt"))
    let b = provider.location(for: root.appendingPathComponent("b.txt"))
    coordinator.submitBatchRename([(a, "b.txt"), (b, "a.txt")], pane: pane, window: nil)
    for _ in 0..<200 where coordinator.isBusy || coordinator.transfers.jobs.isEmpty {
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(coordinator.transfers.jobs.count == 1)
    #expect(coordinator.transfers.jobs.first?.kind == .rename)
    #expect(coordinator.transfers.jobs.first?.state == .completed)
    #expect(
      try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8) == "b.txt")
    #expect(
      try String(contentsOf: root.appendingPathComponent("b.txt"), encoding: .utf8) == "a.txt")
  }
}
