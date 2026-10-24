import FileTermCore
import SwiftUI

struct QuickSelectSheet: View {
  let pane: PaneModel
  @Environment(\.dismiss) private var dismiss
  @State private var criteria = QuickSelectCriteria()
  @FocusState private var focused: Bool

  private var resultingCount: Int { pane.quickSelectPreview(criteria) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Quick Select").font(.headline)
      Picker("Match", selection: $criteria.field) {
        ForEach(SelectionMatchField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).accessibilityIdentifier("quickSelectField")
      TextField(placeholder, text: $criteria.pattern)
        .textFieldStyle(.roundedBorder).focused($focused)
        .accessibilityIdentifier("quickSelectPattern")
        .onSubmit { apply() }
      Picker("Mode", selection: $criteria.mode) {
        ForEach(SelectionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.accessibilityIdentifier("quickSelectMode")
      Text("\(resultingCount) of \(pane.visibleEntries.count) items will be selected")
        .foregroundStyle(.secondary).accessibilityIdentifier("quickSelectCount")
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Select") { apply() }.keyboardShortcut(.defaultAction)
          .disabled(criteria.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }.padding(20).frame(width: 440).onAppear { focused = true }
  }

  private var placeholder: String {
    switch criteria.field {
    case .name: "Name contains, or wildcard such as *.txt"
    case .fileExtension: "Extension, e.g. txt"
    case .tag: "Tag name"
    }
  }

  private func apply() {
    guard !criteria.pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    pane.applyQuickSelect(criteria)
    dismiss()
  }
}
