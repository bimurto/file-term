import AppKit
import SwiftUI

/// One command line of a tool run and what it printed.
struct ToolRunResult: Identifiable {
  let id = UUID()
  let command: String
  let status: Int32
  let stdout: String
  let stderr: String
}

struct ToolOutputView: View {
  let results: [ToolRunResult]
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(results) { result in
            VStack(alignment: .leading, spacing: 4) {
              Text("$ " + result.command).fontWeight(.semibold)
              Text(result.status == 0 ? "Exit code 0" : "Exit code \(result.status)")
                .foregroundStyle(result.status == 0 ? Color.secondary : Color.red)
              section("Output", result.stdout, color: .primary)
              section("Errors", result.stderr, color: .red)
              if result.stdout.isEmpty && result.stderr.isEmpty {
                Text("No output").foregroundStyle(.secondary)
              }
            }
          }
        }
        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityIdentifier("toolOutput")
      HStack {
        Button("Copy All") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(plainText, forType: .string)
        }
        Spacer()
        Button("Close", action: close).keyboardShortcut(.defaultAction)
      }
    }.padding(16).frame(minWidth: 560, minHeight: 380)
  }

  @ViewBuilder private func section(_ title: String, _ text: String, color: Color) -> some View {
    if !text.isEmpty {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(text).foregroundStyle(color)
    }
  }

  private var plainText: String {
    results.map { result in
      var lines = ["$ " + result.command, "Exit code \(result.status)"]
      if !result.stdout.isEmpty { lines.append(result.stdout) }
      if !result.stderr.isEmpty { lines.append(result.stderr) }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
  }
}
