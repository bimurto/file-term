import FileTermCore
import SwiftUI

struct BatchRenameSheet: View {
  let model: BatchRenameModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var model = model
    let rows = model.rows
    let changed = rows.filter(\.isChanged).count
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Batch Rename").font(.headline)
        Spacer()
        Menu("Add Rule") {
          ForEach(RenameRule.Kind.allCases, id: \.self) { kind in
            Button(kind.title) { model.addRule(kind) }
          }
        }.fixedSize().accessibilityIdentifier("renameAddRule")
      }
      ScrollView {
        VStack(spacing: 8) {
          ForEach($model.rules) { $rule in
            RenameRuleEditor(
              rule: $rule, canMoveUp: rule.id != model.rules.first?.id,
              canMoveDown: rule.id != model.rules.last?.id,
              move: { model.moveRule(rule.id, by: $0) }, remove: { model.removeRule(rule.id) })
          }
          if model.rules.isEmpty {
            Text("Add a rule to build the new names.").foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, minHeight: 40)
          }
        }
      }.frame(minHeight: 120, maxHeight: 240)
      Table(rows) {
        TableColumn("Original") { Text($0.original).lineLimit(1).truncationMode(.middle) }
        TableColumn("New") { row in
          Text(row.proposed).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(row.isChanged ? Color.primary : Color.secondary)
            .bold(row.isChanged)
        }
      }.frame(minHeight: 180).accessibilityIdentifier("renamePreview")
      HStack {
        Text("\(changed) of \(rows.count) items will be renamed").foregroundStyle(.secondary)
          .accessibilityIdentifier("renameCount")
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Rename") {
          model.rename()
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(!model.canRename)
          .accessibilityIdentifier("renameRun")
      }
    }.padding(20).frame(width: 720, height: 600)
  }
}

private struct RenameRuleEditor: View {
  @Binding var rule: RenameRule
  let canMoveUp: Bool
  let canMoveDown: Bool
  let move: (Int) -> Void
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(rule.kind.title).bold()
        Spacer()
        Picker("Apply to", selection: $rule.applyTo) {
          Text("Name only").tag(RenameRule.Target.name)
          Text("Extension only").tag(RenameRule.Target.fileExtension)
          Text("Full name").tag(RenameRule.Target.fullName)
        }.frame(width: 220)
        Button {
          move(-1)
        } label: {
          Image(systemName: "chevron.up")
        }
        .disabled(!canMoveUp).accessibilityLabel("Move rule up")
        Button {
          move(1)
        } label: {
          Image(systemName: "chevron.down")
        }
        .disabled(!canMoveDown).accessibilityLabel("Move rule down")
        Button(action: remove) { Image(systemName: "minus") }.accessibilityLabel("Remove rule")
      }
      switch rule.kind {
      case .replaceText:
        HStack {
          TextField("Find", text: $rule.find)
          TextField("Replace with", text: $rule.replacement)
          Picker("Occurrences", selection: $rule.occurrence) {
            Text("First").tag(RenameRule.Occurrence.first)
            Text("Last").tag(RenameRule.Occurrence.last)
            Text("All").tag(RenameRule.Occurrence.all)
          }.frame(width: 130)
          Toggle("Case sensitive", isOn: $rule.caseSensitive)
        }
      case .changeCase:
        Picker("Case", selection: $rule.caseStyle) {
          Text("lower").tag(RenameRule.CaseStyle.lower)
          Text("UPPER").tag(RenameRule.CaseStyle.upper)
          Text("Title").tag(RenameRule.CaseStyle.title)
          Text("Sentence").tag(RenameRule.CaseStyle.sentence)
        }.pickerStyle(.segmented).labelsHidden()
      case .addSequence:
        HStack {
          TextField("Start with", value: $rule.start, format: .number).frame(width: 90)
          TextField("Step", value: $rule.step, format: .number).frame(width: 70)
          TextField("Padding", value: $rule.padding, format: .number).frame(width: 80)
          TextField("Prefix", text: $rule.prefix).frame(width: 80)
          TextField("Suffix", text: $rule.suffix).frame(width: 80)
          PositionEditor(position: $rule.position, index: $rule.positionIndex)
        }
      case .addText:
        HStack {
          TextField("Text", text: $rule.text)
          PositionEditor(position: $rule.position, index: $rule.positionIndex)
        }
      case .addDate:
        HStack {
          Picker("Date", selection: $rule.dateSource) {
            Text("File modified").tag(RenameRule.DateSource.modified)
            Text("File created").tag(RenameRule.DateSource.created)
            Text("Current date").tag(RenameRule.DateSource.now)
          }.frame(width: 190)
          TextField("Format, e.g. yyyy-MM-dd", text: $rule.dateFormat)
          PositionEditor(position: $rule.position, index: $rule.positionIndex)
        }
      }
    }
    .textFieldStyle(.roundedBorder)
    .padding(8)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
  }
}

private struct PositionEditor: View {
  @Binding var position: RenameRule.Position
  @Binding var index: Int

  var body: some View {
    HStack {
      Picker("Position", selection: $position) {
        Text("Start").tag(RenameRule.Position.start)
        Text("End").tag(RenameRule.Position.end)
        Text("At index").tag(RenameRule.Position.index)
      }.frame(width: 130)
      if position == .index {
        TextField("Index", value: $index, format: .number).frame(width: 60)
      }
    }
  }
}
