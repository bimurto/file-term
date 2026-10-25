import Foundation
import Testing

@testable import FileTermCore

struct LocalLinkServiceTests {
  private func sandbox() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test func symlinksUseUniqueUnicodeNamesInSameAndOtherFolder() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("résumé 日本語.txt")
    try Data("original".utf8).write(to: source)
    let other = root.appendingPathComponent("other")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
    let service = LocalLinkService()
    let first = try await service.createSymlink(source: source)
    let second = try await service.createSymlink(source: source)
    let third = try await service.createSymlink(source: source, in: other)
    #expect(first != second)
    #expect(first.deletingLastPathComponent() == root.resolvingSymlinksInPath())
    #expect(third.deletingLastPathComponent() == other.resolvingSymlinksInPath())
    for link in [first, second, third] {
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
          == source.resolvingSymlinksInPath().path)
      #expect(try Data(contentsOf: link) == Data("original".utf8))
    }
  }

  @Test func symlinkCollisionsIncludeDanglingLinksAndNeverOverwrite() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    try Data("source".utf8).write(to: source)
    let occupied = root.appendingPathComponent("file symlink")
    try FileManager.default.createSymbolicLink(
      atPath: occupied.path, withDestinationPath: "missing")
    let second = root.appendingPathComponent("file symlink 2")
    try Data("keep".utf8).write(to: second)
    let result = try await LocalLinkService().createSymlink(source: source)
    #expect(result.lastPathComponent == "file symlink 3")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: occupied.path) == "missing")
    #expect(try String(contentsOf: second, encoding: .utf8) == "keep")
  }

  @Test func aliasesAreFinderAliasesAndResolveUnicodeTargetsWithoutClobbering() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("café 🐈.txt")
    try Data("original".utf8).write(to: source)
    let occupied = root.appendingPathComponent(source.lastPathComponent + " alias")
    try Data("keep".utf8).write(to: occupied)
    let service = LocalLinkService()
    let first = try await service.createAlias(source: source)
    let second = try await service.createAlias(source: source)
    #expect(first != second)
    for alias in [first, second] {
      #expect(try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true)
      let resolved = try URL(resolvingAliasFileAt: alias, options: [.withoutUI, .withoutMounting])
      #expect(resolved.resolvingSymlinksInPath() == source.resolvingSymlinksInPath())
    }
    #expect(try String(contentsOf: occupied, encoding: .utf8) == "keep")
    #expect(try String(contentsOf: source, encoding: .utf8) == "original")
  }

  @Test func aliasCanBeCreatedInAnotherFolder() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("folder")
    let other = root.appendingPathComponent("other")
    for folder in [source, other] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }
    let alias = try await LocalLinkService().createAlias(source: source, in: other)
    #expect(alias.deletingLastPathComponent() == other.resolvingSymlinksInPath())
    #expect(
      try URL(resolvingAliasFileAt: alias).resolvingSymlinksInPath()
        == source.resolvingSymlinksInPath())
  }

  @Test func symlinkLeafIsPreservedEvenWhenDanglingButAliasesRejectIt() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("dangling")
    try FileManager.default.createSymbolicLink(atPath: source.path, withDestinationPath: "missing")
    let service = LocalLinkService()
    let link = try await service.createSymlink(source: source)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == source.path)
    let capability = await service.capability(for: .alias, source: source)
    #expect(!capability.isSupported)
    #expect(capability.disabledReason != nil)
    await #expect(throws: (any Error).self) { try await service.createAlias(source: source) }
  }

  @Test func unsupportedAndUnknownVolumesDisableCreationWithReason() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    try Data().write(to: source)
    for flags in [
      LinkVolumeCapabilities(
        symbolicLinks: false, persistentIDs: false, exclusiveRenaming: false, readOnly: false),
      LinkVolumeCapabilities(
        symbolicLinks: nil, persistentIDs: nil, exclusiveRenaming: nil, readOnly: nil),
      LinkVolumeCapabilities(
        symbolicLinks: true, persistentIDs: true, exclusiveRenaming: true, readOnly: true),
    ] {
      let service = LocalLinkService(volumeCapabilities: { _ in flags })
      for kind in [LocalLinkKind.alias, .symlink] {
        let capability = await service.capability(for: kind, source: source)
        #expect(!capability.isSupported)
        #expect(capability.disabledReason != nil)
      }
      await #expect(throws: (any Error).self) { try await service.createSymlink(source: source) }
      await #expect(throws: (any Error).self) { try await service.createAlias(source: source) }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["file"])
  }

  @Test func concurrentServicesNeverClobberLinksOrAliases() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try Data("payload".utf8).write(to: source)
    for kind in [LocalLinkKind.alias, .symlink] {
      let results = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<12 {
          group.addTask {
            let service = LocalLinkService()
            switch kind {
            case .alias: return try await service.createAlias(source: source)
            case .symlink: return try await service.createSymlink(source: source)
            }
          }
        }
        var results: [URL] = []
        for try await result in group { results.append(result) }
        return results
      }
      #expect(Set(results).count == 12)
      for link in results {
        if kind == .alias {
          #expect(
            try URL(resolvingAliasFileAt: link).resolvingSymlinksInPath()
              == source.resolvingSymlinksInPath())
        } else {
          #expect(try Data(contentsOf: link) == Data("payload".utf8))
        }
      }
    }
  }

  @Test func longUnicodeNamesLeaveRoomForUniqueSuffixes() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent(String(repeating: "猫", count: 84))
    try Data().write(to: source)
    let service = LocalLinkService()
    #expect(await service.capability(for: .symlink, source: source).isSupported)
    let first = try await service.createSymlink(source: source)
    let second = try await service.createSymlink(source: source)
    #expect(first.lastPathComponent.utf8.count <= 255)
    #expect(second.lastPathComponent.utf8.count <= 255)
    #expect(first != second)
  }

  @Test func aliasRequiresPersistentIDsOnSourceAndExclusiveRenameOnDestination() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    try Data().write(to: source)
    let service = LocalLinkService(volumeCapabilities: { _ in
      LinkVolumeCapabilities(
        symbolicLinks: true, persistentIDs: true, exclusiveRenaming: false, readOnly: false)
    })
    #expect(await service.capability(for: .symlink, source: source).isSupported)
    #expect(!(await service.capability(for: .alias, source: source)).isSupported)
    await #expect(throws: (any Error).self) { try await service.createAlias(source: source) }
  }

  @Test func invalidSourceAndDestinationAreDisabled() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("file")
    try Data().write(to: source)
    let service = LocalLinkService()
    for invalid in [
      URL(string: "https://example.com/file")!, root.appendingPathComponent("missing"),
    ] {
      #expect(!(await service.capability(for: .symlink, source: invalid)).isSupported)
      await #expect(throws: (any Error).self) { try await service.createSymlink(source: invalid) }
    }
    #expect(!(await service.capability(for: .alias, source: source, in: source)).isSupported)
    await #expect(throws: (any Error).self) {
      try await service.createAlias(source: source, in: source)
    }
  }
}
