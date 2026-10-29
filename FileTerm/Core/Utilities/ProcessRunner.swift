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

  /// Returns standard output. A nonzero exit throws `Failure` carrying the tool's standard error.
  /// Cancelling the calling task terminates the process.
  @discardableResult
  public static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
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
          if process.terminationStatus == 0 {
            continuation.resume(returning: data)
          } else {
            let text = String(decoding: errorData.get(), as: UTF8.self)
              .trimmingCharacters(in: .whitespacesAndNewlines)
            continuation.resume(
              throwing: Failure(
                tool: (executable as NSString).lastPathComponent,
                status: process.terminationStatus, message: text))
          }
        }
      }
    } onCancel: {
      handle.cancel()
    }
  }
}
