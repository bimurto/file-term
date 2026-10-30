import Foundation
import Testing

@testable import FileTermCore

struct ProcessRunnerTests {
  @Test func captureKeepsBothStreamsAndANonzeroExit() async throws {
    let output = try await ProcessRunner.capture(
      "/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
    #expect(output.status == 3)
    #expect(output.stdout == "out\n")
    #expect(output.stderr == "err\n")
  }

  @Test func captureRunsInTheGivenDirectory() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = try await ProcessRunner.capture("/bin/pwd", [], directory: folder.path)
    #expect(
      URL(fileURLWithPath: output.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        .resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
  }

  @Test func captureOfAMissingProgramThrows() async {
    await #expect(throws: (any Error).self) {
      try await ProcessRunner.capture("/no/such/program", [])
    }
  }

  @Test func cancellingTheTaskStopsTheProcess() async {
    let task = Task { try await ProcessRunner.capture("/bin/sleep", ["30"]) }
    try? await Task.sleep(for: .milliseconds(200))
    task.cancel()
    let started = Date()
    let result = await task.result
    #expect(Date().timeIntervalSince(started) < 5)
    #expect(throws: CancellationError.self) { try result.get() }
  }

  @Test func runStillThrowsFailureWithStandardError() async {
    await #expect(throws: ProcessRunner.Failure.self) {
      try await ProcessRunner.run("/bin/sh", ["-c", "echo bad >&2; exit 2"])
    }
  }
}
