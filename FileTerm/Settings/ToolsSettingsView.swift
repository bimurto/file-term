import FileTermCore
import SwiftUI

/// Settings › Tools: the list of user-defined commands, with Add, Edit and Remove.
struct ToolsSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var selected: UUID?
  @State private var editing: UserTool?
  @State private var isNew = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tools run a shell command on the selected items. They appear in Commands › Tools.")
        .font(.caption).foregroundStyle(.secondary)
      List(selection: $selected) {
        ForEach(settings.tools) { tool in
          HStack {
            Text(tool.name).fontWeight(.medium)
            Text(tool.command).font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary).lineLimit(1)
            Spacer()
          }
          .tag(tool.id).contentShape(Rectangle())
          .onTapGesture(count: 2) { edit(tool) }
        }
      }
      .frame(minHeight: 200).accessibilityIdentifier("toolsList")
      HStack {
        Button("Add") {
          isNew = true
          editing = UserTool(name: "", command: "")
        }.accessibilityIdentifier("addTool")
        Button("Edit") { if let tool = selectedTool { edit(tool) } }.disabled(selectedTool == nil)
        Button("Remove") {
          settings.tools.removeAll { $0.id == selected }
          selected = nil
        }.disabled(selectedTool == nil)
      }
    }
    .sheet(item: $editing) { tool in
      ToolEditor(tool: tool) { saved in
        if isNew {
          settings.tools.append(saved)
        } else if let index = settings.tools.firstIndex(where: { $0.id == saved.id }) {
          settings.tools[index] = saved
        }
      }
    }
  }

  private var selectedTool: UserTool? { settings.tools.first { $0.id == selected } }

  private func edit(_ tool: UserTool) {
    isNew = false
    editing = tool
  }
}

private struct ToolEditor: View {
  @State var tool: UserTool
  let onSave: (UserTool) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Tool").font(.headline)
      TextField("Name", text: $tool.name).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("toolName")
      TextField("Command", text: $tool.command, axis: .vertical)
        .lineLimit(3...6).font(.system(.body, design: .monospaced))
        .textFieldStyle(.roundedBorder).accessibilityIdentifier("toolCommand")
      Text("Insert at the end of the command. Paths are quoted for the shell automatically.")
        .font(.caption).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(ToolPlaceholder.allCases, id: \.self) { placeholder in
          HStack {
            Button("Insert") { insert(placeholder) }
              .accessibilityIdentifier("insert\(placeholder.rawValue)")
            Text(placeholder.rawValue).font(.system(.caption, design: .monospaced))
            Text(placeholder.summary).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Toggle("Run for every selected file", isOn: $tool.runForEachFile)
      Toggle("Enable for remote files", isOn: $tool.enableForRemote)
      Text("Remote items are passed as their remote paths. Nothing is downloaded.")
        .font(.caption).foregroundStyle(.secondary)
      Toggle("Show output", isOn: $tool.showOutput)
      Toggle("Show in Toolbar", isOn: $tool.showInToolbar)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          onSave(tool)
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(!isValid)
      }
    }.padding(20).frame(width: 560)
  }

  private var isValid: Bool {
    !tool.name.trimmingCharacters(in: .whitespaces).isEmpty
      && !tool.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func insert(_ placeholder: ToolPlaceholder) {
    if !tool.command.isEmpty, !tool.command.hasSuffix(" ") { tool.command += " " }
    tool.command += placeholder.rawValue
  }
}
