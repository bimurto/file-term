import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor
struct SyncDialogModelTests {
  private func makeTrees() throws -> (left: URL, right: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let left = root.appendingPathComponent("left")
    let right = root.appendingPathComponent("right")
    try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
    return (left, right)
  }

  private func waitUntilIdle(_ model: SyncDialogModel) async {
    for _ in 0..<200 where model.isAnalyzing { try? await Task.sleep(for: .milliseconds(25)) }
  }

  @Test func synchronizeStaysOffUntilAnalysisFinishesAndOptionChangesRerunIt() async throws {
    let (left, right) = try makeTrees()
    try "a".write(to: left.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "b".write(to: right.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    var submitted: [SyncAction] = []
    let model = SyncDialogModel(
      left: Location(providerID: "local", path: left.path),
      right: Location(providerID: "local", path: right.path), leftLabel: left.path,
      rightLabel: right.path, registry: ProviderRegistry(providers: [LocalFileSystemProvider()])
    ) { actions, _, _ in submitted = actions }
    #expect(!model.canSynchronize)
    model.analyze()
    #expect(model.isAnalyzing && !model.canSynchronize)
    await waitUntilIdle(model)
    #expect(model.actions.map(\.relativePath) == ["a.txt"])
    #expect(model.canSynchronize)

    model.options.deleteOrphans = true
    #expect(model.isAnalyzing && !model.canSynchronize)
    await waitUntilIdle(model)
    #expect(model.actions.map(\.id) == ["a.txt", "b.txt"])
    #expect(model.actions.first { $0.kind == .delete }?.isChecked == true)

    model.setChecked("b.txt", false)
    model.synchronize()
    #expect(submitted.map(\.isChecked) == [true, false])
  }

  @Test func invalidRegexBlocksSynchronize() async throws {
    let (left, right) = try makeTrees()
    let model = SyncDialogModel(
      left: Location(providerID: "local", path: left.path),
      right: Location(providerID: "local", path: right.path), leftLabel: "", rightLabel: "",
      registry: ProviderRegistry(providers: [LocalFileSystemProvider()])
    ) { _, _, _ in }
    model.options.excludes = [SyncFilter(pattern: "(", isRegex: true)]
    await waitUntilIdle(model)
    #expect(model.errorMessage != nil && !model.canSynchronize)
  }
}

@MainActor
struct SyncFavoriteSettingsTests {
  @Test func favoritesPersistAndTheDialogSavesThemWithAllOptions() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    #expect(settings.syncFavorites.isEmpty)
    var saved: [SyncFavorite] = []
    var submitted = false
    let model = SyncDialogModel(
      left: Location(providerID: "local", path: "/tmp/a"),
      right: Location(providerID: "local", path: "/tmp/b"), leftLabel: "/tmp/a",
      rightLabel: "/tmp/b", registry: ProviderRegistry(),
      saveFavorite: { saved.append($0) }, removeFavorite: { _ in },
      submit: { _, _, _ in submitted = true })
    model.options.deleteOrphans = true
    model.favoriteName = "Docs"
    model.addToFavorites()
    #expect(saved.count == 1 && saved[0].options.deleteOrphans && saved[0].name == "Docs")
    #expect(model.favoriteID == saved[0].id && !submitted)
    settings.syncFavorites = saved
    #expect(AppSettings(suite: suite).syncFavorites == saved)
  }
}
