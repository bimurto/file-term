import AppKit
import FileTermCore
import SwiftUI

/// Settings › Editing: which application edits which file extensions.
struct EditingSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var selected: UUID?
  @State private var editing: EditorMapping?
  @State private var isNew = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Commands › Edit opens a file in the application listed for its extension.")
        .font(.caption).foregroundStyle(.secondary)
      Table(settings.editors, selection: $selected) {
        TableColumn("Application") { mapping in
          Text(mapping.displayName)
            .foregroundStyle(
              FileManager.default.fileExists(atPath: mapping.applicationPath)
                ? Color.primary : Color.red)
        }
        TableColumn("Extensions") { mapping in
          Text(mapping.extensions.joined(separator: ", "))
        }
      }
      .frame(minHeight: 200).accessibilityIdentifier("editorsTable")
      HStack {
        Button("Add") {
          isNew = true
          editing = EditorMapping(applicationPath: "", extensions: [])
        }.accessibilityIdentifier("addEditor")
        Button("Edit") { if let mapping = selectedMapping { edit(mapping) } }
          .disabled(selectedMapping == nil)
        Button("Remove") {
          settings.editors.removeAll { $0.id == selected }
          selected = nil
        }.disabled(selectedMapping == nil)
      }
    }
    .sheet(item: $editing) { mapping in
      EditorMappingEditor(mapping: mapping) { saved in
        if isNew {
          settings.editors.append(saved)
        } else if let index = settings.editors.firstIndex(where: { $0.id == saved.id }) {
          settings.editors[index] = saved
        }
      }
    }
  }

  private var selectedMapping: EditorMapping? { settings.editors.first { $0.id == selected } }

  private func edit(_ mapping: EditorMapping) {
    isNew = false
    editing = mapping
  }
}

private struct EditorMappingEditor: View {
  let id: UUID
  @State private var applicationPath: String
  @State private var extensions: String
  let onSave: (EditorMapping) -> Void
  @Environment(\.dismiss) private var dismiss

  init(mapping: EditorMapping, onSave: @escaping (EditorMapping) -> Void) {
    id = mapping.id
    _applicationPath = State(initialValue: mapping.applicationPath)
    _extensions = State(initialValue: mapping.extensions.joined(separator: ", "))
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Editor").font(.headline)
      HStack {
        TextField("Application", text: $applicationPath).textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("editorApplication")
        Button("Choose…") { chooseApplication() }
      }
      TextField("Extensions (for example swift, md, txt)", text: $extensions)
        .textFieldStyle(.roundedBorder).accessibilityIdentifier("editorExtensions")
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          onSave(
            EditorMapping(
              id: id, applicationPath: applicationPath,
              extensions: EditorMapping.parseExtensions(extensions)))
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(!isValid)
      }
    }.padding(20).frame(width: 480)
  }

  private var isValid: Bool {
    applicationPath.hasSuffix(".app")
      && !EditorMapping.parseExtensions(extensions).isEmpty
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.title = "Choose an application"
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.applicationBundle]
    if panel.runModal() == .OK, let url = panel.url { applicationPath = url.path }
  }
}
