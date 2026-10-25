import Foundation
import Testing

@testable import FileTermCore

struct FileUtilityTests {
  private func sandbox() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test func allPathFormatsPreserveUnicodeAndEscapeOnlyAsRequired() throws {
    let url = URL(fileURLWithPath: "/Users/test/雪 day's 100%.txt")
    #expect(try CopyPathFormatter.string(for: url, format: .unix) == "/Users/test/雪 day's 100%.txt")
    #expect(try CopyPathFormatter.string(for: url, format: .fileURL) == url.absoluteString)
    #expect(
      try CopyPathFormatter.string(for: url, format: .decodedURL)
        == "file:///Users/test/雪 day's 100%.txt")
    #expect(try CopyPathFormatter.string(for: url, format: .name) == "雪 day's 100%.txt")
    #expect(
      try CopyPathFormatter.string(for: url, format: .terminal)
        == "'/Users/test/雪 day'\\''s 100%.txt'")
    #expect(
      try CopyPathFormatter.string(for: url, format: .windows) == "\\Users\\test\\雪 day's 100%.txt")
    #expect(CopyPathFormat.allCases.count == 6)
  }

  @Test func shellQuotingProtectsMetacharactersAndDoesNotDecodeTwice() throws {
    let url = URL(fileURLWithPath: "/tmp/$(touch nope);\n%20")
    #expect(
      try CopyPathFormatter.string(for: url, format: .terminal) == "'/tmp/$(touch nope);\n%20'")
    #expect(
      try CopyPathFormatter.string(for: url, format: .decodedURL)
        == "file:///tmp/$(touch nope);\n%20")
    #expect(throws: FileUtilityError.nonLocalURL) {
      try CopyPathFormatter.string(for: URL(string: "https://example.com/a")!, format: .unix)
    }
  }

  @Test func permissionsRoundTripOctalAndCheckboxBits() throws {
    var permissions = try POSIXPermissions(octal: "0754")
    #expect(permissions.mode == 0o754)
    #expect(permissions.octal == "0754")
    #expect(permissions.symbolic == "rwxr-xr--")
    #expect(permissions.contains(.write, for: .owner))
    #expect(!permissions.contains(.write, for: .group))
    permissions.set(.write, for: .group, enabled: true)
    permissions.set(.execute, for: .owner, enabled: false)
    #expect(permissions.mode == 0o674)
    #expect(try POSIXPermissions(octal: "4755").symbolic == "rwsr-xr-x")
    #expect(POSIXPermissions(mode: 0o7000).symbolic == "--S--S--T")
    #expect(POSIXPermissions(mode: 0o1777).symbolic == "rwxrwxrwt")
    #expect(POSIXPermissions(mode: 0o100644).mode == 0o644)
    for value in ["", "888", "-644", " 644", "10000", "64", "0o644"] {
      #expect(throws: FileUtilityError.invalidPermissions) { try POSIXPermissions(octal: value) }
    }
  }

  @Test func streamsKnownChecksumVectorsAndReportsProgress() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file")
    try Data("abc".utf8).write(to: file)
    let vectors: [(ChecksumAlgorithm, String)] = [
      (.md5, "900150983cd24fb0d6963f7d28e17f72"),
      (.sha1, "a9993e364706816aba3e25717850c26c9cd0d89d"),
      (.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ]
    for (algorithm, expected) in vectors {
      let recorder = UtilityProgressRecorder<ChecksumProgress>()
      let digest = try await FileChecksum.calculate(at: file, algorithm: algorithm, chunkSize: 1) {
        await recorder.append($0)
      }
      #expect(digest == expected)
      let updates = await recorder.values
      #expect(updates.map(\.bytesRead) == [0, 1, 2, 3])
      #expect(updates.allSatisfy { $0.totalBytes == 3 })
    }
    try Data().write(to: file)
    #expect(
      try await FileChecksum.calculate(at: file, algorithm: .sha256)
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  @Test func checksumsCancelBetweenChunksAndValidateInputs() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file")
    try Data(repeating: 1, count: 8192).write(to: file)
    let task = Task {
      try await FileChecksum.calculate(at: file, algorithm: .md5, chunkSize: 16) { progress in
        if progress.bytesRead > 0 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    await #expect(throws: FileUtilityError.invalidChunkSize) {
      try await FileChecksum.calculate(at: file, algorithm: .md5, chunkSize: 0)
    }
    await #expect(throws: (any Error).self) {
      try await FileChecksum.calculate(at: root.appendingPathComponent("missing"), algorithm: .md5)
    }
    await #expect(throws: FileUtilityError.notRegularFile) {
      try await FileChecksum.calculate(at: root, algorithm: .md5)
    }
  }

  @Test func folderSizeCountsHiddenNestedFilesButNeverTraversesLinks() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try Data(repeating: 1, count: 7).write(to: root.appendingPathComponent(".hidden"))
    try Data(repeating: 2, count: 11).write(to: nested.appendingPathComponent("file"))
    try FileManager.default.createSymbolicLink(
      at: nested.appendingPathComponent("loop"), withDestinationURL: root)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("file-link"),
      withDestinationURL: nested.appendingPathComponent("file"))
    try FileManager.default.createSymbolicLink(
      atPath: root.appendingPathComponent("broken").path,
      withDestinationPath: "/nonexistent-\(UUID())")
    let recorder = UtilityProgressRecorder<FolderSizeProgress>()
    let size = try await FolderSizeScanner.scan(at: root) { await recorder.append($0) }
    #expect(size.logicalBytes == 18)
    #expect(size.filesCounted == 2)
    let updates = await recorder.values
    #expect(updates.first?.logicalBytes == 0)
    #expect(updates.last == size)
    let linkSize = try await FolderSizeScanner.scan(at: nested.appendingPathComponent("loop"))
    #expect(linkSize.logicalBytes == 0)
    #expect(linkSize.filesCounted == 0)
  }

  @Test func largeChecksumUsesMultipleChunksAndRejectsSymlinks() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("million-a")
    try Data(repeating: 97, count: 1_000_000).write(to: file)
    let digest = try await FileChecksum.calculate(at: file, algorithm: .sha256, chunkSize: 8191)
    #expect(digest == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    await #expect(throws: (any Error).self) {
      try await FileChecksum.calculate(at: link, algorithm: .md5)
    }
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await FileChecksum.calculate(at: file, algorithm: .md5)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
  }

  @Test func sparseFilesAndHardLinksUseLogicalBytesPerEntry() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("sparse")
    try Data().write(to: file)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 8_388_608)
    try handle.close()
    try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("hard-link"))
    let result = try await FolderSizeScanner.scan(at: root)
    #expect(result.logicalBytes == 16_777_216)
    #expect(result.filesCounted == 2)
    #expect(try await FolderSizeScanner.scan(at: file).logicalBytes == 8_388_608)
    let empty = root.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
    #expect(try await FolderSizeScanner.scan(at: empty).logicalBytes == 0)
  }

  @Test func directoryReplacedBySymlinkIsNotTraversed() async throws {
    let root = try sandbox()
    let outside = try sandbox()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    let child = root.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
    try Data(repeating: 1, count: 100).write(to: outside.appendingPathComponent("not-in-tree"))
    await #expect(throws: (any Error).self) {
      try await FolderSizeScanner.scan(at: root) { update in
        if update.itemsVisited == 1 {
          try? FileManager.default.removeItem(at: child)
          try? FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
        }
      }
    }
  }

  @Test func folderScanCancellationAndMissingRootsAreNotPartialSuccesses() async throws {
    let root = try sandbox()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data([1]).write(to: root.appendingPathComponent("file"))
    let task = Task {
      try await FolderSizeScanner.scan(at: root) { _ in withUnsafeCurrentTask { $0?.cancel() } }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    await #expect(throws: (any Error).self) {
      try await FolderSizeScanner.scan(at: root.appendingPathComponent("missing"))
    }
  }
}

private actor UtilityProgressRecorder<Value: Sendable> {
  var values: [Value] = []
  func append(_ value: Value) { values.append(value) }
}
