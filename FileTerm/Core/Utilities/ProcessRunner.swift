import Foundation

/// Runs a command-line tool to completion without blocking the caller's thread.
public enum ProcessRunner {
  public struct Failure: LocalizedError, Sendable {
    public let tool: String
    public let status: Int32
    public let message: String
    public var errorDescription: String? {
      message.isEmpty ? "\(tool) failed (exit \(status))." : message
    }
  }

  private final class Handle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ process: Process) {
      lock.lock()
      defer { lock.unlock() }
      self.process = process
      if cancelled { process.terminate() }
    }

    func cancel() {
      lock.lock()
      defer { lock.unlock() }
      cancelled = true
      process?.terminate()
    }
  }

  private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()
    func set(_ data: Data) {
      lock.lock()
      value = data
      lock.unlock()
    }
    func get() -> Data {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  public struct Output: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
  }

  private struct Finished: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
  }

  /// Returns standard output. A nonzero exit throws `Failure` carrying the tool's standard error.
  /// Cancelling the calling task terminates the process.
  @discardableResult
  public static func run(
    _ executable: String, _ arguments: [String], environment: [String: String] = [:]
  ) async throws -> Data {
    let finished = try await execute(executable, arguments, environment: environment)
    guard finished.status == 0 else {
      let text = String(decoding: finished.stderr, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw Failure(
        tool: (executable as NSString).lastPathComponent, status: finished.status, message: text)
    }
    return finished.stdout
  }

  /// Returns the exit status with both output streams; a nonzero exit is not an error. Throws only
  /// if the process cannot start, or `CancellationError` once the calling task is cancelled (the
  /// process is terminated first).
  public static func capture(
    _ executable: String, _ arguments: [String], directory: String? = nil
  ) async throws -> Output {
    let finished = try await execute(executable, arguments, directory: directory)
    try Task.checkCancellation()
    return Output(
      status: finished.status, stdout: String(decoding: finished.stdout, as: UTF8.self),
      stderr: String(decoding: finished.stderr, as: UTF8.self))
  }

  private static func execute(
    _ executable: String, _ arguments: [String], environment: [String: String] = [:],
    directory: String? = nil
  ) async throws -> Finished {
    let handle = Handle()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          let process = Process()
          let output = Pipe()
          let errors = Pipe()
          process.executableURL = URL(fileURLWithPath: executable)
          process.arguments = arguments
          process.standardOutput = output
          process.standardError = errors
          process.standardInput = FileHandle.nullDevice
          if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
          if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
          }
          do { try process.run() } catch {
            continuation.resume(throwing: error)
            return
          }
          handle.set(process)
          let errorData = Collector()
          let group = DispatchGroup()
          group.enter()
          DispatchQueue.global().async {
            errorData.set((try? errors.fileHandleForReading.readToEnd()) ?? Data())
            group.leave()
          }
          let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
          group.wait()
          process.waitUntilExit()
          continuation.resume(
            returning: Finished(
              status: process.terminationStatus, stdout: data, stderr: errorData.get()))
        }
      }
    } onCancel: {
      handle.cancel()
    }
  }
}
