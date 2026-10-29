import Foundation
import Testing

@testable import FileTermCore

struct CompareTests {
  private let left = URL(fileURLWithPath: "/tmp/a.txt")
  private let right = URL(fileURLWithPath: "/tmp/b.txt")

  @Test func fileMergeNeedsTheAppAndTheLauncher() {
    let dev = "/Applications/Xcode.app/Contents/Developer"
    let both: Set = [dev + "/Applications/FileMerge.app", "/usr/bin/opendiff"]
    let invocation = CompareTool.fileMerge.invocation(
      left: left, right: right, fileExists: both.contains, developerDirectory: dev)
    #expect(
      invocation == .init(executable: "/usr/bin/opendiff", arguments: [left.path, right.path]))
    // opendiff is only a stub without Xcode: no app, no tool.
    #expect(
      CompareTool.fileMerge.invocation(
        left: left, right: right, fileExists: { $0 == "/usr/bin/opendiff" },
        developerDirectory: nil) == nil)
    #expect(
      CompareTool.fileMerge.invocation(
        left: left, right: right, fileExists: { _ in false }, developerDirectory: dev) == nil)
  }

  @Test func eachToolBuildsItsOwnArguments() {
    let code = "/opt/homebrew/bin/code"
    let vscode = CompareTool.vscode.invocation(
      left: left, right: right,
      fileExists: { ["/Applications/Visual Studio Code.app", code].contains($0) },
      developerDirectory: nil)
    #expect(vscode == .init(executable: code, arguments: ["--diff", left.path, right.path]))
    let ksdiff = CompareTool.kaleidoscope.invocation(
      left: left, right: right,
      fileExists: { ["/Applications/Kaleidoscope.app", "/usr/local/bin/ksdiff"].contains($0) },
      developerDirectory: nil)
    #expect(ksdiff?.arguments == [left.path, right.path])
  }

  private func file(_ path: String, provider: String = "local", kind: FileEntry.Kind = .file)
    -> FileEntry
  {
    FileEntry(
      location: Location(providerID: provider, path: path),
      name: (path as NSString).lastPathComponent, kind: kind)
  }

  @Test func comparesTwoFilesOfOnePaneOrOneFileFromEachPane() {
    let a = file("/x/a")
    let b = file("/x/b")
    let c = file("/y/c")
    let sameFolder = CompareSelection.resolve(active: [a, b], other: [])
    #expect(sameFolder == .pair(left: a.url, right: b.url))
    let acrossPanes = CompareSelection.resolve(active: [a], other: [c])
    #expect(acrossPanes == .pair(left: a.url, right: c.url))
    // Two in the active pane win over a selection in the other pane.
    let both = CompareSelection.resolve(active: [a, b], other: [c])
    #expect(both == .pair(left: a.url, right: b.url))
  }

  @Test func otherSelectionsExplainWhatIsNeeded() {
    let a = file("/x/a")
    let b = file("/x/b")
    let c = file("/y/c")
    let hint = "Select two files, or one file in each pane."
    #expect(CompareSelection.resolve(active: [], other: []) == .unavailable(hint))
    #expect(CompareSelection.resolve(active: [a], other: []) == .unavailable(hint))
    #expect(CompareSelection.resolve(active: [a, b, c], other: []) == .unavailable(hint))
    #expect(
      CompareSelection.resolve(active: [a, file("/x/d", kind: .directory)], other: [])
        == .unavailable("Compare works on files, not folders."))
    #expect(
      CompareSelection.resolve(active: [a], other: [file("/r", provider: "sftp:1")])
        == .unavailable("Compare works on local files only."))
  }
}

extension FileEntry {
  fileprivate var url: URL { URL(fileURLWithPath: location.path) }
}
