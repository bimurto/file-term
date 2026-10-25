import Foundation
import XCTest

@testable import FileTerm

final class FilePreviewTests: XCTestCase {
  private func fixture(_ data: Data) throws -> (URL, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("sample.txt")
    try data.write(to: url)
    return (folder, url)
  }

  func testTextSavePreservesPermissionsAndUTF8BOM() throws {
    let (folder, url) = try fixture(Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8))
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    var document = try PreviewTextDocument(url: url)
    XCTAssertEqual(document.text, "hello")
    try document.save("edited")
    XCTAssertEqual(try Data(contentsOf: url), Data([0xEF, 0xBB, 0xBF]) + Data("edited".utf8))
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    try document.save("second save")
    XCTAssertEqual(document.text, "second save")
  }

  func testExternalChangeIsNotOverwritten() throws {
    let (folder, url) = try fixture(Data("original".utf8))
    defer { try? FileManager.default.removeItem(at: folder) }
    var document = try PreviewTextDocument(url: url)
    try Data("external".utf8).write(to: url)
    XCTAssertThrowsError(try document.save("my edits"))
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
    XCTAssertEqual(document.text, "original")
  }

  func testExternalWriteDuringStagingAbortsPublicationAndRetainsEdits() throws {
    let (folder, url) = try fixture(Data("original".utf8))
    defer { try? FileManager.default.removeItem(at: folder) }
    var document = try PreviewTextDocument(url: url)
    let edits = "unsaved user edits"
    XCTAssertThrowsError(
      try document.save(
        edits,
        beforePublication: {
          try Data("external during staging".utf8).write(to: url)
        })
    ) { error in
      guard case PreviewTextError.changed = error else {
        return XCTFail("Expected an external-change conflict, got \(error)")
      }
    }
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external during staging")
    XCTAssertEqual(document.text, "original")
    // The caller's edit buffer remains untouched, and can be saved to another file.
    XCTAssertEqual(edits, "unsaved user edits")
    let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    XCTAssertEqual(remaining, ["sample.txt"], "Unpublished staging file must be removed")
  }

  func testSuccessfulSaveRetainsRecoverableOriginalBackup() throws {
    let (folder, url) = try fixture(Data("original".utf8))
    defer { try? FileManager.default.removeItem(at: folder) }
    var document = try PreviewTextDocument(url: url)
    try document.save("edited")
    let backups = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains(".fileterm-backup-") }
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try String(contentsOf: XCTUnwrap(backups.first), encoding: .utf8), "original")
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "edited")
  }

  func testRejectsBinaryInvalidEncodingAndOversizedText() throws {
    for data in [
      Data([0, 1, 2]), Data([0xFF, 0x80]),
      Data(repeating: 65, count: PreviewTextDocument.maximumBytes + 1),
    ] {
      let (folder, url) = try fixture(data)
      defer { try? FileManager.default.removeItem(at: folder) }
      XCTAssertThrowsError(try PreviewTextDocument(url: url))
    }
  }

  func testUTF16RoundTrip() throws {
    let data = Data([0xFF, 0xFE]) + "Snow 雪\r\n".data(using: .utf16LittleEndian)!
    let (folder, url) = try fixture(data)
    defer { try? FileManager.default.removeItem(at: folder) }
    var document = try PreviewTextDocument(url: url)
    XCTAssertEqual(document.text, "Snow 雪\r\n")
    try document.save("Edited 雪\r\n")
    XCTAssertEqual(
      try Data(contentsOf: url),
      Data([0xFF, 0xFE]) + "Edited 雪\r\n".data(using: .utf16LittleEndian)!)
  }
}
