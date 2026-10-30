import AppKit
import FileTermCore
import SwiftUI

/// Runs user tools as queue jobs and shows their output.
@MainActor final class ToolRunner {
  private struct Failure: LocalizedError {
    let failed: Int
    let total: Int
    let status: Int32
    var errorDescription: String? {
      total == 1
        ? "The command exited with code \(status)."
        : "\(failed) of \(total) commands failed (last exit code \(status))."
    }
  }

  private final class JobReference { var id: UUID? }

  private let fileOperations: FileOperationCoordinator
  private var windows: [UUID: FileUtilityWindowController] = [:]

  init(fileOperations: FileOperationCoordinator) { self.fileOperations = fileOperations }

  /// Why the tool cannot run for these panes, or nil when it can.
  static func disabledReason(
    for tool: UserTool, source: Location?, target: Location?, selectionCount: Int
  ) -> String? {
    guard let source else { return "Open a folder first." }
    for location in [source, target].compactMap({ $0 }) {
      if location.providerID.hasPrefix("archive:") {
        return "Tools cannot run inside an archive opened as a folder."
      }
      if location.providerID != "local" && !tool.enableForRemote {
        return "Turn on “Enable for remote files” for this tool in Settings › Tools."
      }
    }
    if tool.runForEachFile && selectionCount == 0 {
      return "Select one or more items to run this tool for each of them."
    }
    return nil
  }

  @discardableResult
  func run(_ tool: UserTool, context: ToolCommandBuilder.Context, source: Location) -> UUID? {
    let lines = ToolCommandBuilder.expand(tool, context: context)
    guard !lines.isEmpty else { return nil }
    let directory = source.providerID == "local" ? source.path : NSHomeDirectory()
    let queue = fileOperations.transfers
    let reference = JobReference()
    let id = queue.submit(
      kind: .tool, resources: FileOperationCoordinator.resources(for: [source]),
      retrySafe: false, sourceLabels: [tool.name],
      destinationLabel: fileOperations.describe(source)
    ) { [weak self] control in
      var results: [ToolRunResult] = []
      var summary = TransferSummary()
      for line in lines {
        try await control.checkpoint()
        let output = try await ProcessRunner.capture("/bin/sh", ["-c", line], directory: directory)
        results.append(
          ToolRunResult(
            command: line, status: output.status, stdout: output.stdout, stderr: output.stderr))
        if let id = reference.id {
          queue.log(id, "$ \(line)")
          queue.log(id, "Exit code \(output.status)")
        }
        if output.status == 0 { summary.succeeded += 1 } else { summary.failed += 1 }
      }
      await self?.fileOperations.refresh?()
      if tool.showOutput { self?.showOutput(results, title: tool.name) }
      if let last = results.last(where: { $0.status != 0 }) {
        throw Failure(failed: summary.failed, total: lines.count, status: last.status)
      }
      return summary
    }
    reference.id = id
    return id
  }

  private func showOutput(_ results: [ToolRunResult], title: String) {
    let id = UUID()
    let controller = FileUtilityWindowController(title: title)
    controller.window?.styleMask.insert(.resizable)
    controller.window?.contentView = NSHostingView(
      rootView: ToolOutputView(results: results) { [weak controller] in controller?.close() })
    controller.onClose = { [weak self] in self?.windows[id] = nil }
    windows[id] = controller
    controller.showWindow(nil)
  }
}
