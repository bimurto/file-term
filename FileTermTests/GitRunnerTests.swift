import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@Suite(.serialized)
@MainActor struct GitRunnerTests {
  private let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("git-\(UUID().uuidString)")

  @discardableResult
  private func git(_ folder: URL, _ args: String...) async throws -> String {
    let data = try await ProcessRunner.run(
      GitCommand.executable, ["-C", folder.path] + args,
      environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"])
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func repository(_ name: String) async throws -> URL {
    let folder = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try await git(folder, "init", "-b", "main")
    try await git(folder, "config", "user.name", "Tester")
    try await git(folder, "config", "user.email", "tester@example.com")
    try await git(folder, "config", "commit.gpgsign", "false")
    return folder
  }

  private func finish(_ coordinator: FileOperationCoordinator, _ id: UUID) async -> TransferJob? {
    for _ in 0..<1000 {
      if let job = coordinator.transfers.jobs.first(where: { $0.id == id }), job.state.isTerminal {
        return job
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }

  private func logs(_ coordinator: FileOperationCoordinator, _ id: UUID) -> [String] {
    coordinator.transfers.logs.filter { $0.jobID == id }.map(\.message)
  }

  @Test func addStagesOnlyTheGivenPathsAndLogsTheOutput() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = try await repository("a")
    try Data("one".utf8).write(to: repo.appendingPathComponent("a b.txt"))
    try Data("two".utf8).write(to: repo.appendingPathComponent("other.txt"))
    let coordinator = FileOperationCoordinator()
    let runner = GitRunner(fileOperations: coordinator)

    let id = runner.run(.add([repo.appendingPathComponent("a b.txt").path]), root: repo.path)
    let job = await finish(coordinator, id)

    #expect(job?.state == .completed && job?.kind == .git)
    let status = try await git(repo, "status", "--porcelain")
    #expect(status.contains("A  \"a b.txt\"") && status.contains("?? other.txt"))
    let log = logs(coordinator, id)
    #expect(log.contains { $0.hasPrefix("$ git -C ") && $0.contains(" add -- ") })
    #expect(log.contains("Exit code 0"))
  }

  @Test func addAllThenCommitRecordsTheMessage() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = try await repository("b")
    try Data("one".utf8).write(to: repo.appendingPathComponent("one.txt"))
    try Data("two".utf8).write(to: repo.appendingPathComponent("two.txt"))
    let coordinator = FileOperationCoordinator()
    let runner = GitRunner(fileOperations: coordinator)

    _ = await finish(coordinator, runner.run(.addAll, root: repo.path))
    let message = "feat: it's \"quoted\"\n\nsecond paragraph"
    let id = runner.run(.commit(message: message), root: repo.path)
    let job = await finish(coordinator, id)

    #expect(job?.state == .completed)
    #expect(try await git(repo, "log", "-1", "--format=%B") == message)
    #expect(try await git(repo, "show", "--stat", "--format=", "HEAD").contains("two.txt"))
    #expect(logs(coordinator, id).contains { $0.contains("feat: it's") })
  }

  @Test func aFailingCommandFailsTheJobWithGitsReason() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = try await repository("c")
    let coordinator = FileOperationCoordinator()
    let runner = GitRunner(fileOperations: coordinator)

    let id = runner.run(.add([repo.appendingPathComponent("missing.txt").path]), root: repo.path)
    let job = await finish(coordinator, id)

    #expect(job?.state == .failed)
    #expect(job?.error?.contains("missing.txt") == true)
    #expect(job?.canRetry == false)
    #expect(logs(coordinator, id).contains { $0.hasPrefix("Exit code ") && $0 != "Exit code 0" })
  }

  @Test func pushAndPullMoveCommitsThroughARemote() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let bare = root.appendingPathComponent("remote.git")
    try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
    try await git(bare, "init", "--bare", "-b", "main")
    let first = try await repository("first")
    try await git(first, "remote", "add", "origin", bare.path)
    try Data("v1".utf8).write(to: first.appendingPathComponent("f.txt"))
    try await git(first, "add", "--all")
    try await git(first, "commit", "-m", "one")
    try await git(first, "push", "-u", "origin", "main")
    let second = root.appendingPathComponent("second")
    try await git(root, "clone", bare.path, second.path)
    let coordinator = FileOperationCoordinator()
    let runner = GitRunner(fileOperations: coordinator)

    try Data("v2".utf8).write(to: first.appendingPathComponent("g.txt"))
    try await git(first, "add", "--all")
    try await git(first, "commit", "-m", "two")
    let push = await finish(coordinator, runner.run(.push, root: first.path))
    #expect(push?.state == .completed)
    #expect(try await git(bare, "log", "-1", "--format=%s", "main") == "two")

    let pullID = runner.run(.pull, root: second.path)
    let pull = await finish(coordinator, pullID)
    #expect(pull?.state == .completed)
    #expect(FileManager.default.fileExists(atPath: second.appendingPathComponent("g.txt").path))
    #expect(logs(coordinator, pullID).contains("Exit code 0"))
  }
}
