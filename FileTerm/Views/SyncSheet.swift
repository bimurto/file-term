import FileTermCore
import SwiftUI

struct SyncSheet: View {
  let model: SyncDialogModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: 12) {
      Text("Sync").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
        GridRow {
          Text("Left").foregroundStyle(.secondary)
          Text(model.leftLabel).lineLimit(1).truncationMode(.middle)
            .accessibilityIdentifier("syncLeftPath")
        }
        GridRow {
          Text("Right").foregroundStyle(.secondary)
          Text(model.rightLabel).lineLimit(1).truncationMode(.middle)
            .accessibilityIdentifier("syncRightPath")
        }
      }
      Picker("Direction", selection: $model.options.direction) {
        Text("Left → Right").tag(SyncOptions.Direction.leftToRight)
        Text("Right → Left").tag(SyncOptions.Direction.rightToLeft)
        Text("Both ways").tag(SyncOptions.Direction.bothWays)
      }.pickerStyle(.segmented).accessibilityIdentifier("syncDirection")
      HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading) {
          Toggle("Synchronize subfolders", isOn: $model.options.subfolders)
          Toggle("Synchronize hidden items", isOn: $model.options.hidden)
          Toggle("Add items", isOn: $model.options.addItems)
          Toggle("Don’t add empty folders", isOn: $model.options.skipEmptyFolders)
            .disabled(!model.options.addItems)
        }
        VStack(alignment: .leading) {
          Text("Update items when").foregroundStyle(.secondary)
          Toggle("Modification date is older", isOn: $model.options.updateWhenOlder)
          Toggle("Size differs", isOn: $model.options.updateWhenSizeDiffers)
          Toggle("Delete orphaned items", isOn: $model.options.deleteOrphans)
            .foregroundStyle(.red)
            .disabled(model.options.direction == .bothWays)
            .help(
              "Both ways never deletes: without a sync history, a deletion cannot be told from a new item."
            )
            .accessibilityIdentifier("syncDeleteOrphans")
        }
      }
      Text("Items are compared by modification date and size, not byte by byte.")
        .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("syncComparisonNote")
      if model.hasRemoteSide {
        Text(
          "Copies to remote locations do not keep modification dates, so use “Size differs” there."
        ).font(.callout).foregroundStyle(.orange)
      }
      HStack {
        Text("Time offset")
        TextField("0", value: $model.options.timeOffset, format: .number)
          .frame(width: 70).textFieldStyle(.roundedBorder)
        Picker("Unit", selection: $model.options.offsetUnit) {
          Text("seconds").tag(SyncOptions.OffsetUnit.seconds)
          Text("hours").tag(SyncOptions.OffsetUnit.hours)
        }.labelsHidden().frame(width: 100)
        Text("added to the right side’s dates").foregroundStyle(.secondary)
      }
      excludes
      Table(model.actions) {
        TableColumn("") { action in
          Toggle(
            "", isOn: Binding(get: { action.isChecked }, set: { model.setChecked(action.id, $0) })
          ).labelsHidden().disabled(!action.isRunnable)
        }.width(24)
        TableColumn("Action") { action in
          Text(label(action)).foregroundStyle(action.kind == .delete ? .red : .primary)
        }.width(110)
        TableColumn("Path") { action in
          Text(action.relativePath + (action.isDirectory ? "/" : ""))
            .foregroundStyle(action.kind == .delete ? .red : .primary)
            .lineLimit(1).truncationMode(.middle)
        }
        TableColumn("Left") { Text(detail($0.left)).monospacedDigit().foregroundStyle(.secondary) }
          .width(150)
        TableColumn("Right") {
          Text(detail($0.right)).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(150)
      }
      .frame(minHeight: 160).accessibilityIdentifier("syncActions")
      HStack {
        status
        Spacer()
        Button("Cancel") {
          model.cancel()
          dismiss()
        }.keyboardShortcut(.cancelAction)
        Button("Synchronize") {
          model.synchronize()
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(!model.canSynchronize)
        .accessibilityIdentifier("syncRun")
      }
    }
    .padding(20).frame(width: 760, height: 640)
    .onAppear { model.analyze() }
  }

  @ViewBuilder private var status: some View {
    if model.isAnalyzing {
      HStack {
        ProgressView().controlSize(.small)
        Text("Analyzing…")
      }
    } else if let message = model.errorMessage {
      Text(message).foregroundStyle(.red)
    } else {
      Text("\(model.checkedCount) of \(model.actions.count) actions selected")
        .foregroundStyle(.secondary)
    }
  }

  private var excludes: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Exclude items")
        Button {
          model.options.excludes.append(SyncFilter(pattern: ""))
        } label: {
          Image(systemName: "plus")
        }.accessibilityLabel("Add filter")
      }
      ForEach($model.options.excludes) { $filter in
        HStack {
          TextField(
            filter.isRegex ? "Regular expression" : "Glob, e.g. *.log", text: $filter.pattern
          )
          .textFieldStyle(.roundedBorder)
          Picker("Type", selection: $filter.isRegex) {
            Text("Glob").tag(false)
            Text("Regex").tag(true)
          }.labelsHidden().frame(width: 80)
          if !filter.isValid {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
              .help("Not a valid regular expression")
          }
          Button {
            model.options.excludes.removeAll { $0.id == filter.id }
          } label: {
            Image(systemName: "minus")
          }.accessibilityLabel("Remove filter")
        }
      }
    }
  }

  private func label(_ action: SyncAction) -> String {
    let arrow = action.towards == .right ? "→" : "←"
    switch action.kind {
    case .add: return "Add \(arrow)"
    case .update: return "Update \(arrow)"
    case .delete: return "Delete \(action.towards == .right ? "right" : "left")"
    case .conflict: return action.isRunnable ? "Conflict" : "Conflict (file vs folder)"
    }
  }

  private func detail(_ entry: FileEntry?) -> String {
    guard let entry else { return "—" }
    guard entry.kind == .file else { return "folder" }
    let size = entry.size.map { $0.formatted(.byteCount(style: .file)) } ?? "?"
    let date = entry.modifiedAt?.formatted(date: .numeric, time: .shortened) ?? "?"
    return "\(size), \(date)"
  }
}
