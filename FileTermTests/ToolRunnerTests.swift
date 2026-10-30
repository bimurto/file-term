import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@Suite(.serialized)
@MainActor struct ToolRunnerTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func finish(_ coordinator: FileOperationCoordinator, _ id: UUID?) async -> TransferJob? {
    for _ in 0..<500 {
      if let job = coordinator.transfers.jobs.first(where: { $0.id == id }), job.state.isTerminal {
        return job
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }

  private func messages(_ coordinator: FileOperationCoordinator, _ id: UUID?) -> [String] {
    coordinator.transfers.logs.filter { $0.jobID == id }.map(\.message)
  }

  @Test func aToolRunsInTheSourceFolderAndLogsItsExitCode() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("hello".utf8).write(to: root.appendingPathComponent("a b.txt"))
    let coordinator = FileOperationCoordinator()
    let runner = ToolRunner(fileOperations: coordinator)
    let tool = UserTool(name: "Copy", command: "cp $SOURCE_SELECTION_NAMES copy.txt")
    let source = Location(providerID: "local", path: root.path)

    let id = runner.run(
      tool,
      context: .init(
        sourcePath: root.path, sourceSelection: [root.appendingPathComponent("a b.txt").path]),
      source: source)
    let job = await finish(coordinator, id)

    #expect(job?.state == .completed)
    #expect(job?.kind == .tool)
    #expect(
      try String(contentsOf: root.appendingPathComponent("copy.txt"), encoding: .utf8) == "hello")
    #expect(messages(coordinator, id).contains("Exit code 0"))
  }

  @Test func aNonzeroExitFailsTheJobAndIsLogged() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let coordinator = FileOperationCoordinator()
    let runner = ToolRunner(fileOperations: coordinator)
    let id = runner.run(
      UserTool(name: "Fail", command: "echo nope >&2; exit 3"),
      context: .init(sourcePath: root.path),
      source: Location(providerID: "local", path: root.path))
    let job = await finish(coordinator, id)

    #expect(job?.state == .failed)
    #expect(job?.error?.contains("code 3") == true)
    #expect(messages(coordinator, id).contains("Exit code 3"))
  }

  @Test func runForEveryFileRunsOncePerItemAndReportsEachExit() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let coordinator = FileOperationCoordinator()
    let runner = ToolRunner(fileOperations: coordinator)
    let tool = UserTool(
      name: "Touch", command: "touch done-$SOURCE_SELECTION_NAMES", runForEachFile: true)
    let id = runner.run(
      tool, context: .init(sourcePath: root.path, sourceSelection: ["/x/one", "/x/two"]),
      source: Location(providerID: "local", path: root.path))
    let job = await finish(coordinator, id)

    #expect(job?.state == .completed)
    #expect(job?.summary.succeeded == 2)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("done-one").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("done-two").path))
    #expect(messages(coordinator, id).filter { $0 == "Exit code 0" }.count == 2)
  }

  @Test func nothingRunsForEachFileWithoutASelection() {
    let runner = ToolRunner(fileOperations: FileOperationCoordinator())
    let tool = UserTool(name: "Each", command: "echo $SOURCE_SELECTION_PATHS", runForEachFile: true)
    #expect(
      runner.run(
        tool, context: .init(sourcePath: "/tmp"),
        source: Location(providerID: "local", path: "/tmp")) == nil)
  }

  @Test func availabilityFollowsTheToolsRules() {
    let local = Location(providerID: "local", path: "/tmp")
    let remote = Location(providerID: "sftp.x", path: "/srv")
    let archive = Location(providerID: "archive:1", path: "/")
    var tool = UserTool(name: "T", command: "true")

    #expect(
      ToolRunner.disabledReason(for: tool, source: nil, target: nil, selectionCount: 0) != nil)
    #expect(
      ToolRunner.disabledReason(for: tool, source: local, target: nil, selectionCount: 0) == nil)
    #expect(
      ToolRunner.disabledReason(for: tool, source: remote, target: nil, selectionCount: 0) != nil)
    #expect(
      ToolRunner.disabledReason(for: tool, source: local, target: remote, selectionCount: 0) != nil)
    tool.enableForRemote = true
    #expect(
      ToolRunner.disabledReason(for: tool, source: remote, target: local, selectionCount: 0) == nil)
    #expect(
      ToolRunner.disabledReason(for: tool, source: archive, target: nil, selectionCount: 0) != nil)
    tool.runForEachFile = true
    #expect(
      ToolRunner.disabledReason(for: tool, source: local, target: nil, selectionCount: 0) != nil)
    #expect(
      ToolRunner.disabledReason(for: tool, source: local, target: nil, selectionCount: 2) == nil)
  }
}
