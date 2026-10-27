import AppKit
import FileTermCore
import SwiftUI
import UniformTypeIdentifiers

/// Compact, app-wide operation history; controls act on the shared scheduler.
struct TransferActivitiesPanel: View {
  let queue: TransferQueue

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Activities", systemImage: "arrow.left.arrow.right").font(.headline)
        Spacer()
        Text("\(queue.jobs.filter { !$0.state.isTerminal }.count) active")
          .font(.caption).foregroundStyle(.secondary)
      }
      if queue.jobs.isEmpty {
        Text("No activities yet. File operations will appear here.")
          .foregroundStyle(.secondary).accessibilityIdentifier("activitiesEmpty")
        Spacer(minLength: 0)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(queue.jobs) { job in
              TransferJobRow(job: job, queue: queue)
              Divider()
            }
          }
        }
      }
    }
    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain).accessibilityIdentifier("panel.Activities")
  }
}

private struct TransferJobRow: View {
  let job: TransferJob
  let queue: TransferQueue

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(job.kind.rawValue.capitalized).fontWeight(.medium)
        Text(job.state.rawValue.capitalized).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        controls
      }
      ForEach(Array(job.sourceLabels.enumerated()), id: \.offset) { _, source in
        Text("From: \(source)").lineLimit(1).truncationMode(.middle).help(source)
      }
      if let destination = job.destinationLabel {
        Text("To: \(destination)").lineLimit(1).truncationMode(.middle).help(destination)
      }
      if !job.state.isTerminal {
        if let total = job.totalBytes, total > 0 {
          ProgressView(value: Double(job.bytesTransferred), total: Double(total))
            .accessibilityLabel("Transfer progress")
        } else if job.state == .running {
          ProgressView().controlSize(.small).accessibilityLabel("Transfer size unknown")
        }
        Text(progressDescription).foregroundStyle(.secondary).monospacedDigit()
      }
      if job.state.isTerminal {
        Text(
          "\(job.summary.succeeded) succeeded · \(job.summary.skipped) skipped · \(job.summary.failed) failed"
        )
        .foregroundStyle(.secondary)
      }
      if let error = job.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
          .textSelection(.enabled)
      }
      if let hint = job.hint { Text(hint).foregroundStyle(.secondary).textSelection(.enabled) }
    }
    .font(.caption)
    .accessibilityElement(children: .contain).accessibilityIdentifier("transfer.\(job.id)")
  }

  @ViewBuilder private var controls: some View {
    if job.state == .queued {
      control("Move earlier", symbol: "arrow.up", id: "earlier") { queue.move(job.id, by: -1) }
        .disabled(queue.jobs.first(where: { $0.state == .queued })?.id == job.id)
      control("Move later", symbol: "arrow.down", id: "later") { queue.move(job.id, by: 1) }
        .disabled(queue.jobs.last(where: { $0.state == .queued })?.id == job.id)
    }
    if job.state == .running || job.state == .queued {
      control("Pause", symbol: "pause", id: "pause") { queue.pause(job.id) }
    }
    if job.state == .paused {
      control("Resume", symbol: "play", id: "resume") { queue.resume(job.id) }
    }
    if !job.state.isTerminal {
      control("Cancel", symbol: "xmark", id: "cancel") { queue.cancel(job.id) }
    }
    if job.state == .failed {
      control("Retry", symbol: "arrow.clockwise", id: "retry") { queue.retry(job.id) }
        .disabled(!job.canRetry)
    }
  }

  private func control(_ title: String, symbol: String, id: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) { Image(systemName: symbol) }
      .buttonStyle(.borderless).help(title).accessibilityLabel(title)
      .accessibilityIdentifier("transfer.\(id).\(job.id)")
  }

  private var progressDescription: String {
    let bytes = job.bytesTransferred.formatted(.byteCount(style: .file))
    let speed = Int64(min(Double(Int64.max - 1024), max(0, job.bytesPerSecond)))
      .formatted(.byteCount(style: .file))
    let eta = job.eta.map { "\(Int(min($0, 86_400 * 365)))s remaining" } ?? "ETA unknown"
    return "\(bytes) · \(speed)/s · \(eta)"
  }
}

struct TransferLogsPanel: View {
  let queue: TransferQueue
  @State private var exportError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Logs", systemImage: "list.bullet.rectangle").font(.headline)
        Spacer()
        Button("Copy All") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(queue.exportedLogs, forType: .string)
        }.accessibilityIdentifier("copyTransferLogs").disabled(queue.logs.isEmpty)
        Button("Export…") { export() }
          .accessibilityIdentifier("exportTransferLogs").disabled(queue.logs.isEmpty)
      }
      if let exportError {
        Label(exportError, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.red).textSelection(.enabled)
          .accessibilityIdentifier("transferLogExportError")
      }
      if queue.logs.isEmpty {
        Text("No logs yet. Operation details will appear here.")
          .foregroundStyle(.secondary).accessibilityIdentifier("logsEmpty")
        Spacer(minLength: 0)
      } else {
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(queue.logs) { entry in
              Text(entry.text).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
          }
        }
      }
    }
    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain).accessibilityIdentifier("panel.Logs")
  }

  private func export() {
    let panel = NSSavePanel()
    panel.title = "Export Transfer Logs"
    panel.nameFieldStringValue = "FileTerm-transfers.txt"
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try queue.exportedLogs.write(to: url, atomically: true, encoding: .utf8)
        exportError = nil
      } catch {
        exportError = "Could not export logs: \(error.localizedDescription)"
      }
    }
  }
}
