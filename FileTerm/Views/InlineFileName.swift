import FileTermCore
import SwiftUI

struct InlineFileName: View {
  @Bindable var pane: PaneModel
  let entry: FileEntry

  var body: some View {
    if pane.renamingLocation == entry.location {
      FileNameEditor(pane: pane, entry: entry).id(entry.location)
    } else {
      Text(entry.name)
    }
  }
}

private struct FileNameEditor: View {
  let pane: PaneModel
  let entry: FileEntry
  @State private var name: String
  @FocusState private var isFocused: Bool

  init(pane: PaneModel, entry: FileEntry) {
    self.pane = pane
    self.entry = entry
    _name = State(initialValue: entry.name)
  }

  var body: some View {
    TextField("Name", text: $name)
      .textFieldStyle(.plain)
      .focused($isFocused)
      .task { isFocused = true }
      .onSubmit {
        pane.renamingLocation = nil
        pane.onRename?(entry.location, name)
      }
      .onExitCommand { pane.renamingLocation = nil }
      .accessibilityIdentifier("rename.\(entry.name)")
      .accessibilityValue(name)
  }
}
