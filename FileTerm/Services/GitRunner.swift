import AppKit
import FileTermCore

/// Runs Commands › Source Control actions as queue jobs and writes git's output to Logs.
@MainActor final class GitRunner {
  private struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  @MainActor private final class JobReference { var id: UUID? }

  private static let maximumLogLines = 500

  private let fileOperations: FileOperationCoordinator

  init(fileOperations: FileOperationCoordinator) { self.fileOperations = fileOperations }

  @discardableResult
  func run(_ command: GitCommand, root: String) -> UUID {
    let queue = fileOperations.transfers
    let reference = JobReference()
    let id = queue.submit(
      kind: .git, resources: [root], retrySafe: false, sourceLabels: [command.title],
      destinationLabel: root
    ) { [weak self] control in
      try await control.checkpoint()
      let output: ProcessRunner.Output
      do {
        output = try await ProcessRunner.capture(
          GitCommand.executable, command.arguments(root: root),
          environment: GitCommand.environment.merging(LoginShellPath.environment()) { $1 })
      } catch {
        if let id = reference.id {
          queue.log(id, "Could not start git: \(error.localizedDescription)")
        }
        throw error
      }
      if let id = reference.id {
        queue.log(id, command.logLine(root: root))
        let lines = (output.stdout + "\n" + output.stderr).split(whereSeparator: \.isNewline)
          .map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for line in lines.prefix(Self.maximumLogLines) { queue.log(id, line) }
        if lines.count > Self.maximumLogLines {
          queue.log(id, "… \(lines.count - Self.maximumLogLines) more lines")
        }
        queue.log(id, "Exit code \(output.status)")
      }
      await self?.fileOperations.refresh?()
      guard output.status == 0 else {
        let reason = output.stderr.split(whereSeparator: \.isNewline).last.map(String.init)
        throw Failure(message: reason ?? "git exited with code \(output.status).")
      }
      return TransferSummary(succeeded: 1)
    }
    reference.id = id
    return id
  }

  /// Asks for the commit message. Returns nil when cancelled or empty.
  static func askForCommitMessage() -> String? {
    let alert = NSAlert()
    alert.messageText = "Commit staged changes"
    alert.informativeText = "Enter the commit message."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
    field.placeholderString = "Message"
    alert.accessoryView = field
    alert.addButton(withTitle: "Commit")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let message = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty ? nil : message
  }
}
