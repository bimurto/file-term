import Darwin
import Foundation
import XCTest

@testable import FileTerm

final class FileMetadataTests: XCTestCase {
  private func fixture() throws -> (folder: URL, file: URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("sample.txt")
    try Data("hello".utf8).write(to: file)
    return (folder, file)
  }

  func testLoadAndFinderMetadataRoundTrip() async throws {
    let (folder, file) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    let service = FileMetadataService()
    let original = try await service.load(file)
    XCTAssertEqual(original.url, file)
    XCTAssertEqual(original.bytes, 5)
    XCTAssertFalse(original.isSymbolicLink)
    XCTAssertFalse(original.hidden)
    XCTAssertEqual(original.ownerID, getuid())
    XCTAssertGreaterThan(original.created.timeIntervalSince1970, 0)
    if let reason = original.commentDisabledReason { throw XCTSkip(reason) }
    let tags = ["Work\n2", "Personal", "雪"]
    let comment = "Finder comment\nWith Unicode 雪"
    try await service.apply(.tags(tags), to: original)
    try await service.apply(.comment(comment), to: original)
    let edited = try await service.load(file)
    XCTAssertEqual(edited.tags, tags)
    XCTAssertEqual(edited.comment, comment)
    XCTAssertNil(edited.commentDisabledReason)
    try await service.apply(.tags([]), to: edited)
    try await service.apply(.comment(""), to: edited)
    let cleared = try await service.load(file)
    XCTAssertEqual(cleared.tags, [])
    XCTAssertEqual(cleared.comment, "")
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
  }

  func testPermissionsAndOctalValidation() async throws {
    let (folder, file) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    let service = FileMetadataService()
    let original = try await service.load(file)
    let mode = try FileMetadataService.permissions(from: "0640")
    try await service.apply(.permissions(mode), to: original)
    let edited = try await service.load(file)
    XCTAssertEqual(edited.mode, 0o640)
    XCTAssertEqual(try FileMetadataService.permissions(from: "4755"), 0o4755)
    for invalid in ["", "64", "888", "10000", "-755", " 755"] {
      XCTAssertThrowsError(try FileMetadataService.permissions(from: invalid))
    }
    do {
      try await service.apply(.permissions(0o10000), to: edited)
      XCTFail("Accepted mode outside 07777")
    } catch FileMetadataService.MetadataError.invalidPermissions {}
  }

  func testLockedRoundTripWhenFilesystemPermits() async throws {
    let (folder, file) = try fixture()
    // Ensure cleanup even when an assertion or the unlock step fails.
    defer {
      _ = file.withUnsafeFileSystemRepresentation { chflags($0!, 0) }
      try? FileManager.default.removeItem(at: folder)
    }
    let service = FileMetadataService()
    let original = try await service.load(file)
    XCTAssertFalse(original.locked)
    do {
      try await service.apply(.locked(true), to: original)
    } catch let error as NSError
      where error.domain == NSPOSIXErrorDomain
      && [Int(EPERM), Int(EACCES), Int(ENOTSUP)].contains(error.code)
    {
      throw XCTSkip(
        "Filesystem does not permit locking this fixture: \(error.localizedDescription)")
    }
    let locked = try await service.load(file)
    XCTAssertTrue(locked.locked)
    try await service.apply(.locked(false), to: locked)
    let unlocked = try await service.load(file)
    XCTAssertFalse(unlocked.locked)
  }

  func testReplacementInodeIsRejected() async throws {
    let (folder, file) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    let service = FileMetadataService()
    let original = try await service.load(file)
    // Keep the original inode alive to prevent inode recycling making the test flaky.
    let moved = folder.appendingPathComponent("original.txt")
    try FileManager.default.moveItem(at: file, to: moved)
    try Data("replacement".utf8).write(to: file)
    for change: FileMetadataService.Change in [
      .comment("stale"), .permissions(0o777), .locked(true),
    ] {
      do {
        try await service.apply(change, to: original)
        XCTFail("Edited a replacement item using stale metadata")
      } catch FileMetadataService.MetadataError.changedItem {}
    }
    let replacement = try await service.load(file)
    XCTAssertNotEqual(replacement.inode, original.inode)
    XCTAssertFalse(replacement.locked)
    XCTAssertEqual(replacement.comment, "")
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "replacement")
  }

  func testSymbolicLinkEditsDeniedWithoutChangingTarget() async throws {
    let (folder, file) = try fixture()
    defer { try? FileManager.default.removeItem(at: folder) }
    let service = FileMetadataService()
    let target = try await service.load(file)
    let link = folder.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let linked = try await service.load(link)
    XCTAssertTrue(linked.isSymbolicLink)
    XCTAssertNotNil(linked.commentDisabledReason)
    let changes: [FileMetadataService.Change] = [
      .tags(["not allowed"]), .comment("not allowed"), .permissions(0o777),
      .owner(target.ownerID), .group(target.groupID), .locked(true),
    ]
    for change in changes {
      do {
        try await service.apply(change, to: linked)
        XCTFail("Allowed editing through a symbolic link")
      } catch FileMetadataService.MetadataError.symbolicLink {}
    }
    let after = try await service.load(file)
    XCTAssertEqual(after.mode, target.mode)
    XCTAssertEqual(after.tags, target.tags)
    XCTAssertEqual(after.comment, target.comment)
    XCTAssertEqual(after.locked, target.locked)
  }
}
