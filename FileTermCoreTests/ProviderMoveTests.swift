import Foundation
import Testing

@testable import FileTermCore

@Suite struct ProviderMoveTests {
  private func engine(
    _ providers: [any FileSystemProvider],
    resolve: @escaping LocationConflictResolver = { _ in ConflictResolution(decision: .skip) }
  ) -> ProviderTransfer {
    ProviderTransfer(
      registry: ProviderRegistry(providers: providers), control: TransferControl(), resolve: resolve
    )
  }

  private func at(_ provider: MemoryProvider, _ path: String) -> Location {
    Location(providerID: provider.id, path: path)
  }

  @Test func moveDeletesTheSourcesAfterACleanCopy() async throws {
    let first = MemoryProvider(id: "one")
    let second = MemoryProvider(id: "two")
    await first.seedDirectory("/tree")
    await first.seedFile("/tree/a.txt", "alpha")
    await first.seedFile("/b.txt", "beta")
    let summary = try await engine([first, second]).move(
      sources: [at(first, "/tree"), at(first, "/b.txt")], to: at(second, "/"))
    #expect(summary.failed == 0 && summary.skipped == 0)
    #expect(await second.text("/tree/a.txt") == "alpha")
    #expect(await second.text("/b.txt") == "beta")
    #expect(await first.paths() == ["/"])
  }

  @Test func moveKeepsEverySourceWhenAnItemIsSkipped() async throws {
    let first = MemoryProvider(id: "one")
    let second = MemoryProvider(id: "two")
    await first.seedFile("/a.txt", "new")
    await first.seedFile("/b.txt", "beta")
    await second.seedFile("/a.txt", "old")
    let summary = try await engine([first, second]).move(
      sources: [at(first, "/a.txt"), at(first, "/b.txt")], to: at(second, "/"))
    #expect(summary.skipped == 1)
    #expect(await second.text("/a.txt") == "old")
    #expect(await second.text("/b.txt") == "beta")
    #expect(await first.text("/a.txt") == "new")
    #expect(await first.text("/b.txt") == "beta")
  }

  @Test func moveKeepsTheSourceWhenTheCopyFails() async throws {
    let first = MemoryProvider(id: "one")
    let second = MemoryProvider(id: "two")
    await first.seedFile("/a.txt", "alpha")
    await second.configure(failWritesAfterChunks: 1)
    await #expect(throws: (any Error).self) {
      try await engine([first, second]).move(sources: [at(first, "/a.txt")], to: at(second, "/"))
    }
    #expect(await first.text("/a.txt") == "alpha")
  }

  @Test func moveIntoTheSameFolderIsRefusedAndNothingIsLost() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedFile("/a.txt", "alpha")
    await #expect(throws: FileSystemError.io("The items are already in this folder.")) {
      try await engine([memory], resolve: { _ in ConflictResolution(decision: .replace) })
        .move(sources: [at(memory, "/a.txt")], to: at(memory, "/"))
    }
    #expect(await memory.text("/a.txt") == "alpha")
  }

  @Test func renameMovesWithinTheFolderAndRefusesAnExistingName() async throws {
    let memory = MemoryProvider(id: "mem")
    await memory.seedFile("/a.txt", "alpha")
    await memory.seedFile("/b.txt", "beta")
    let registry = ProviderRegistry(providers: [memory])
    let renamed = try await ProviderItemOperations.rename(
      at(memory, "/a.txt"), to: "c.txt", registry: registry)
    #expect(renamed.path == "/c.txt")
    #expect(await memory.text("/c.txt") == "alpha")
    await #expect(throws: FileSystemError.destinationExists) {
      try await ProviderItemOperations.rename(
        at(memory, "/c.txt"), to: "b.txt", registry: registry)
    }
    await #expect(throws: (any Error).self) {
      try await ProviderItemOperations.rename(at(memory, "/c.txt"), to: "x/y", registry: registry)
    }
    #expect(await memory.text("/b.txt") == "beta")
  }

  @Test func newFolderPicksTheNextFreeName() async throws {
    let memory = MemoryProvider(id: "mem")
    let registry = ProviderRegistry(providers: [memory])
    let first = try await ProviderItemOperations.createFolder(
      in: at(memory, "/"), registry: registry)
    let second = try await ProviderItemOperations.createFolder(
      in: at(memory, "/"), registry: registry)
    #expect(first.path == "/untitled folder")
    #expect(second.path == "/untitled folder 2")
  }
}
