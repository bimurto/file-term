import Foundation
import Testing

@testable import FileTermCore

struct GitTests {
  @Test func findsTheRepositoryAtOrAboveTheFolder() {
    let exists: (String) -> Bool = { $0 == "/work/app/.git" }
    #expect(GitRepository.root(from: "/work/app", fileExists: exists) == "/work/app")
    #expect(GitRepository.root(from: "/work/app/Sources/Core", fileExists: exists) == "/work/app")
    #expect(GitRepository.root(from: "/work/app/", fileExists: exists) == "/work/app")
    #expect(GitRepository.root(from: "/work", fileExists: exists) == nil)
  }

  @Test func theNearestRepositoryWins() {
    let exists: (String) -> Bool = { $0 == "/work/.git" || $0 == "/work/app/vendor/lib/.git" }
    #expect(
      GitRepository.root(from: "/work/app/vendor/lib/src", fileExists: exists)
        == "/work/app/vendor/lib")
    #expect(GitRepository.root(from: "/work/app", fileExists: exists) == "/work")
  }

  @Test func theFilesystemRootCanBeARepositoryAndNothingLoopsForever() {
    #expect(GitRepository.root(from: "/a/b", fileExists: { $0 == "/.git" }) == "/")
    #expect(GitRepository.root(from: "/a/b", fileExists: { _ in false }) == nil)
    #expect(GitRepository.root(from: "relative/path", fileExists: { _ in true }) == nil)
  }

  @Test func aGitFileMarksAWorktreeAndARealFolderIsFound() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = root.appendingPathComponent("a/b")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GitRepository.root(from: nested.path) != root.path)
    try Data("gitdir: /elsewhere".utf8).write(to: root.appendingPathComponent(".git"))
    #expect(GitRepository.root(from: nested.path) == root.path)
  }

  @Test func commandsBuildOneArgumentPerPathAndMessage() {
    let root = "/repo with space"
    #expect(
      GitCommand.add(["/repo with space/a b.txt", "/repo with space/-x"]).arguments(root: root)
        == ["-C", root, "add", "--", "/repo with space/a b.txt", "/repo with space/-x"])
    #expect(GitCommand.addAll.arguments(root: root) == ["-C", root, "add", "--all"])
    #expect(
      GitCommand.commit(message: "fix: it's \"quoted\"\n\nbody").arguments(root: root)
        == ["-C", root, "commit", "-m", "fix: it's \"quoted\"\n\nbody"])
    #expect(GitCommand.push.arguments(root: root) == ["-C", root, "push"])
    #expect(GitCommand.pull.arguments(root: root) == ["-C", root, "pull"])
  }

  @Test func gitIsNeverAllowedToWaitForInput() {
    #expect(GitCommand.environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(GitCommand.environment["GIT_MERGE_AUTOEDIT"] == "no")
  }

  @Test func theLogLineShowsTheCommand() {
    #expect(GitCommand.pull.logLine(root: "/r") == "$ git -C /r pull")
  }
}
