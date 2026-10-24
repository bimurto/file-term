import FileTermCore
import SwiftUI

/// Fuzzy launcher for commands and destinations (Esc).
struct QuickOpenSheet: View {
  let sources: [any QuickOpenSource]
  let onChoose: (QuickOpenItem) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var highlighted = 0
  @FocusState private var focused: Bool

  private var results: [QuickOpenItem] { QuickOpen.search(query, sources: sources) }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Type a command or folder", text: $query)
        .textFieldStyle(.roundedBorder).focused($focused)
        .accessibilityIdentifier("quickOpenField")
        .onSubmit { run(at: highlighted) }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.downArrow) {
          highlighted = min(highlighted + 1, max(results.count - 1, 0))
          return .handled
        }
        .onKeyPress(.upArrow) {
          highlighted = max(highlighted - 1, 0)
          return .handled
        }
      let items = results
      if items.isEmpty {
        Text("No matches").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
      } else {
        ScrollViewReader { proxy in
          List(Array(items.enumerated()), id: \.element.id) { index, item in
            HStack {
              Image(systemName: symbol(item.kind)).frame(width: 18)
              VStack(alignment: .leading, spacing: 1) {
                Text(item.title).foregroundStyle(item.isEnabled ? .primary : .secondary)
                if !item.subtitle.isEmpty {
                  Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              }
              Spacer()
              Text(label(item.kind)).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2).contentShape(Rectangle())
            .listRowBackground(index == highlighted ? Color.accentColor.opacity(0.25) : .clear)
            .onTapGesture { run(at: index) }
            .id(index)
            .accessibilityIdentifier("quickOpenItem.\(item.id)")
          }
          .listStyle(.plain).frame(height: 260)
          .onChange(of: highlighted) { _, value in proxy.scrollTo(value) }
        }
      }
      HStack {
        Text("↩ run · ↑↓ choose · esc close").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }
    .padding(16).frame(width: 520)
    .defaultFocus($focused, true)
    .onAppear {
      focused = true
      DispatchQueue.main.async { focused = true }
    }
  }

  private func run(at index: Int) {
    let items = results
    guard items.indices.contains(index) else { return }
    let item = items[index]
    guard item.isEnabled else { return }
    onChoose(item)
    dismiss()
  }

  private func symbol(_ kind: QuickOpenKind) -> String {
    switch kind {
    case .command: "command"
    case .folder: "folder"
    case .recent: "clock"
    case .device: "externaldrive"
    case .favorite: "star"
    case .application: "app"
    case .renamePreset: "pencil"
    }
  }

  private func label(_ kind: QuickOpenKind) -> String {
    switch kind {
    case .command: "Command"
    case .folder: "Folder"
    case .recent: "Recent"
    case .device: "Device"
    case .favorite: "Favorite"
    case .application: "Application"
    case .renamePreset: "Rename Preset"
    }
  }
}
