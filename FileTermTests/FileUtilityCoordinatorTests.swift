import FileTermCore
import XCTest

@testable import FileTerm

@MainActor final class FileUtilityCoordinatorTests: XCTestCase {
  func testChecksumComparisonAndAlgorithmReset() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let model = ChecksumUtilityModel(url: url)
    model.calculate()
    while model.isRunning { await Task.yield() }
    XCTAssertEqual(model.digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    model.expectedDigest = "  BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD\n"
    XCTAssertTrue(model.checksumMatches)
    model.expectedDigest = "0000"
    XCTAssertEqual(model.comparisonDescription, "Checksums do not match")
    model.clearResult()
    XCTAssertNil(model.digest)
    XCTAssertNil(model.comparisonDescription)
  }

  func testFolderResultsDoNotApplyAfterRefresh() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("abc".utf8).write(to: folder.appendingPathComponent("a"))
    defer { try? FileManager.default.removeItem(at: root) }
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    await pane.navigate(to: provider.location(for: root))
    let model = FolderSizesUtilityModel(pane: pane, folders: pane.visibleEntries)
    await pane.refresh()
    model.start()
    while model.isRunning { await Task.yield() }
    XCTAssertTrue(pane.calculatedSizes.isEmpty)
  }
}
